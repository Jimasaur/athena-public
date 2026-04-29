class DemoScenarioSeedService
  DEMO_TO_NUMBER = "+14155551234"

  attr_reader :slug

  def initialize(slug:)
    @slug = slug.to_s
  end

  def call
    scenario = DemoScenarioCatalog.fetch(slug)

    ActiveRecord::Base.transaction do
      remove_existing_demo_records(scenario)
      customer = upsert_customer(scenario)
      conversation = create_conversation(scenario, customer)
      transcript_event = create_transcript_event(scenario, conversation)
      conversation.update!(transcript_call_event: transcript_event)
      create_messages(scenario, conversation)
      call_state = create_call_state(scenario, conversation)
      create_state_patch_event(scenario, conversation, call_state)
      summary_event = create_summary_event(scenario, conversation, call_state, transcript_event)
      draft = create_action_draft(scenario, conversation, call_state, summary_event)
      create_action_draft_events(scenario, conversation, call_state, draft, transcript_event)
      create_demo_idea_capture(scenario, conversation, call_state, transcript_event)
      conversation
    end
  end

  private

  def remove_existing_demo_records(scenario)
    Conversation.where(twilio_call_sid: call_id_for(scenario)).find_each(&:destroy)
    CallState.where(call_id: call_id_for(scenario)).destroy_all
  end

  def upsert_customer(scenario)
    caller = scenario[:caller]
    customer = Customer.find_or_initialize_by(phone_number: caller[:phone])
    customer.assign_attributes(
      name: caller[:name],
      greeting_name: caller[:greeting_name],
      customer_portrait: caller[:portrait],
      metadata: (customer.metadata || {}).merge(
        "demo" => true,
        "sms_consent" => true,
        "demo_scenario_slug" => scenario[:slug],
        "preferred_demo_space" => scenario[:space]
      )
    )
    customer.save!
    customer
  end

  def create_conversation(scenario, customer)
    Conversation.create!(
      customer: customer,
      channel: "voice",
      status: "completed",
      summary: scenario[:summary],
      agent_name: scenario[:agent_name],
      call_started_at: demo_time - 12.minutes,
      twilio_call_sid: call_id_for(scenario)
    )
  end

  def create_transcript_event(scenario, conversation)
    conversation.call_events.create!(
      twilio_call_sid: call_id_for(scenario),
      status: "post_call_transcription",
      direction: "inbound",
      from_number: scenario.dig(:caller, :phone),
      to_number: demo_to_number,
      transcription: scenario[:summary],
      data: {
        "type" => "post_call_transcription",
        "data" => {
          "agent_name" => scenario[:agent_name],
          "analysis" => analysis_payload(scenario),
          "transcript" => transcript_payload(scenario)
        }
      },
      created_at: demo_time - 2.minutes
    )
  end

  def create_messages(scenario, conversation)
    scenario[:transcript].each_with_index do |(role, content), index|
      conversation.messages.create!(
        role: TranscriptRoleNormalizer.call(role),
        content: content,
        sent_at: demo_time - 11.minutes + (index * 35).seconds
      )
    end
  end

  def create_call_state(scenario, conversation)
    call_state = CallState.ensure_for_conversation(
      conversation,
      provider: scenario[:provider],
      call_id: call_id_for(scenario),
      status: "completed",
      use_case_slug: scenario[:slug],
      space: space_slug(scenario[:space])
    )
    review_status = review_status_for(scenario[:action_status])
    call_state.update!(
      review_status: review_status,
      state: (call_state.state || {}).deep_merge(
        "status" => "completed",
        "review_status" => review_status,
        "intent" => scenario[:intent],
        "risk" => scenario[:risk],
        "facts" => scenario[:facts],
        "allowed_actions" => [ "lookup", "summarize", "draft", "capture_idea", "human_review" ],
        "handoff_required" => scenario.dig(:risk, "level") == "high",
        "next_best_question" => scenario[:next_best_question],
        "demo" => {
          "scenario_slug" => scenario[:slug],
          "goal" => scenario[:demo_goal],
          "showcase" => scenario[:showcase]
        }
      )
    )
    call_state
  end

  def create_state_patch_event(scenario, conversation, call_state)
    call_state.sidecar_events.create!(
      conversation: conversation,
      source: scenario[:sidecar_source],
      kind: "state_patch.applied",
      provider: scenario[:provider],
      payload: {
        "patched_fields" => [ "intent", "risk", "next_best_question" ],
        "intent" => scenario[:intent],
        "risk" => scenario[:risk],
        "next_best_question" => scenario[:next_best_question],
        "changes_call_behavior" => true
      },
      evidence: {
        "scenario_slug" => scenario[:slug],
        "transcript_excerpt" => scenario[:transcript].detect { |role, _text| role == "user" }&.last
      },
      changes_call_behavior: true,
      requires_review: scenario.dig(:risk, "level").in?([ "medium", "high" ]),
      occurred_at: demo_time - 8.minutes
    )
  end

  def create_summary_event(scenario, conversation, call_state, transcript_event)
    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "call_summarizer",
      kind: "summary.created",
      provider: scenario[:provider],
      payload: {
        "summary" => scenario[:summary],
        "operator_takeaway" => scenario[:operator_takeaway],
        "scenario_slug" => scenario[:slug]
      },
      evidence: {
        "transcript_call_event_id" => transcript_event.id
      },
      requires_review: true,
      occurred_at: demo_time - 90.seconds
    )
  end

  def create_action_draft(scenario, conversation, call_state, summary_event)
    status = scenario[:action_status]
    reviewed_at = status == ActionDraft::PENDING_APPROVAL_STATUS ? nil : demo_time - 45.seconds
    side_effect = external_side_effect_for(status, scenario)

    call_state.action_drafts.create!(
      conversation: conversation,
      kind: "follow_up_message",
      status: status,
      created_by: "demo_follow_up_drafter",
      recipient: {
        "name" => scenario.dig(:caller, :name),
        "phone" => scenario.dig(:caller, :phone)
      },
      content: {
        "body" => scenario[:draft_body],
        "source_event_id" => summary_event.id,
        "scenario_slug" => scenario[:slug],
        "demo_goal" => scenario[:demo_goal]
      },
      approval_required: true,
      approved_by: reviewed_at.present? ? "demo_operator" : nil,
      approved_at: reviewed_at,
      external_side_effect: side_effect
    )
  end

  def create_action_draft_events(scenario, conversation, call_state, draft, transcript_event)
    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "demo_follow_up_drafter",
      kind: "action_draft.created",
      provider: scenario[:provider],
      payload: {
        "action_draft_id" => draft.id,
        "action_kind" => draft.kind,
        "scenario_slug" => scenario[:slug]
      },
      evidence: {
        "transcript_call_event_id" => transcript_event.id
      },
      requires_review: draft.pending_approval?,
      occurred_at: demo_time - 1.minute
    )

    case draft.status
    when ActionDraft::APPROVED_STATUS
      create_review_event(scenario, conversation, call_state, draft, "action_draft.approved")
    when ActionDraft::REJECTED_STATUS
      create_review_event(scenario, conversation, call_state, draft, "action_draft.rejected", reason: "Reviewer kept this for staff verification.")
    when ActionDraft::EXECUTED_STATUS
      create_review_event(scenario, conversation, call_state, draft, "action_draft.approved")
      create_execution_event(scenario, conversation, call_state, draft, "external_action.executed")
    when ActionDraft::EXECUTION_FAILED_STATUS
      create_review_event(scenario, conversation, call_state, draft, "action_draft.approved")
      create_execution_event(scenario, conversation, call_state, draft, "external_action.failed", requires_review: true)
    end
  end

  def create_review_event(scenario, conversation, call_state, draft, kind, reason: nil)
    payload = {
      "action_draft_id" => draft.id,
      "action_kind" => draft.kind,
      "status" => draft.status,
      "reviewer" => "demo_operator"
    }
    payload["reason"] = reason if reason.present?

    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "human_review",
      kind: kind,
      provider: scenario[:provider],
      payload: payload,
      evidence: { "action_draft_id" => draft.id },
      occurred_at: demo_time - 40.seconds
    )
  end

  def create_execution_event(scenario, conversation, call_state, draft, kind, requires_review: false)
    side_effect = draft.external_side_effect || {}

    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "demo_twilio_sms_executor",
      kind: kind,
      provider: "demo_twilio",
      payload: {
        "action_draft_id" => draft.id,
        "action_kind" => draft.kind,
        "provider" => "demo_twilio",
        "twilio_message_sid" => side_effect["external_id"],
        "error" => side_effect["error"],
        "mode" => "demo"
      }.compact,
      evidence: { "action_draft_id" => draft.id },
      requires_review: requires_review,
      occurred_at: demo_time - 30.seconds
    )
  end

  def create_demo_idea_capture(scenario, conversation, call_state, transcript_event)
    idea = conversation.idea_captures.create!(
      title: scenario[:title],
      category: scenario[:space],
      department: "Revenue Cycle",
      status: "captured",
      problem: scenario[:summary],
      proposed_solution: scenario[:operator_takeaway],
      impact: scenario[:facts].join(" "),
      next_step: scenario[:next_best_question],
      payload: {
        "demo" => true,
        "scenario_slug" => scenario[:slug],
        "showcase" => scenario[:showcase],
        "caller" => scenario[:caller],
        "workshop_prompt" => "What would need to be true to pilot this safely in 30-60 days?"
      }
    )

    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "athena_idea_capture",
      kind: "idea_capture.captured",
      provider: scenario[:provider],
      payload: {
        "idea_capture_id" => idea.id,
        "title" => idea.title,
        "category" => idea.category,
        "scenario_slug" => scenario[:slug]
      },
      evidence: {
        "transcript_call_event_id" => transcript_event.id,
        "idea_capture_id" => idea.id
      },
      requires_review: true,
      occurred_at: demo_time - 50.seconds
    )
  end

  def analysis_payload(scenario)
    {
      "call_successful" => "success",
      "call_summary_title" => scenario[:short_title],
      "transcript_summary" => scenario[:summary],
      "data_collection_results_list" => [
        {
          "data_collection_id" => "intent",
          "value" => scenario.dig(:intent, "label"),
          "rationale" => "Detected from the caller's stated goal and follow-up request."
        },
        {
          "data_collection_id" => "risk",
          "value" => scenario.dig(:risk, "level"),
          "rationale" => Array(scenario.dig(:risk, "reasons")).join(", ")
        },
        {
          "data_collection_id" => "next_best_question",
          "value" => scenario[:next_best_question],
          "rationale" => "Generated by the sidecar after observing the call."
        }
      ]
    }
  end

  def transcript_payload(scenario)
    scenario[:transcript].each_with_index.map do |(role, message), index|
      {
        "role" => TranscriptRoleNormalizer.call(role),
        "speaker" => role,
        "message" => message,
        "time_in_call_secs" => index * 35
      }
    end
  end

  def external_side_effect_for(status, scenario)
    base = {
      "type" => "send_message",
      "mode" => "demo",
      "dry_run" => true,
      "scenario_slug" => scenario[:slug]
    }

    case status
    when ActionDraft::PENDING_APPROVAL_STATUS
      base.merge("executed" => false)
    when ActionDraft::APPROVED_STATUS
      base.merge("approved" => true, "executed" => false, "reviewed_at" => (demo_time - 45.seconds).iso8601)
    when ActionDraft::REJECTED_STATUS
      base.merge("approved" => false, "executed" => false, "reviewed_at" => (demo_time - 45.seconds).iso8601, "rejection_reason" => "Reviewer kept this for staff verification.")
    when ActionDraft::EXECUTED_STATUS
      base.merge("approved" => true, "executed" => true, "reviewed_at" => (demo_time - 45.seconds).iso8601, "executed_at" => (demo_time - 30.seconds).iso8601, "provider" => "demo_twilio", "external_id" => demo_message_sid(scenario))
    when ActionDraft::EXECUTION_FAILED_STATUS
      base.merge("approved" => true, "executed" => false, "reviewed_at" => (demo_time - 45.seconds).iso8601, "attempted_at" => (demo_time - 30.seconds).iso8601, "provider" => "demo_twilio", "external_id" => demo_message_sid(scenario), "error" => "Demo guardrail blocked automated send; route this item to staff review.")
    else
      base
    end
  end

  def review_status_for(action_status)
    case action_status
    when ActionDraft::PENDING_APPROVAL_STATUS
      "pending"
    when ActionDraft::REJECTED_STATUS
      "rejected"
    else
      "approved"
    end
  end

  def call_id_for(scenario)
    "DEMO-#{scenario[:slug].upcase.gsub(/[^A-Z0-9]+/, "-")}"
  end

  def demo_message_sid(scenario)
    "SM-DEMO-#{scenario[:slug].upcase.gsub(/[^A-Z0-9]+/, "-")}"
  end

  def demo_to_number
    AgentSetting.where.not(twilio_number: [ nil, "" ]).order(:id).pick(:twilio_number).presence || DEMO_TO_NUMBER
  end

  def space_slug(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").sub(/_+\z/, "")
  end

  def demo_time
    @demo_time ||= Time.current.change(usec: 0)
  end
end
