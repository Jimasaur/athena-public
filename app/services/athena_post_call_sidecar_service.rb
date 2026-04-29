class AthenaPostCallSidecarService
  def initialize(conversation:, call_event:)
    @conversation = conversation
    @call_event = call_event
  end

  def call
    call_state = CallState.ensure_for_conversation(
      @conversation,
      provider: @conversation.call_state&.provider.presence || "openai_realtime",
      call_id: call_id,
      status: @conversation.status.presence || "completed"
    )

    summary_event = create_summary_event(call_state)
    draft = create_action_draft(call_state, summary_event)
    create_draft_event(call_state, draft, summary_event)

    { ok: true, call_state: call_state, action_draft: draft }
  end

  private

  def call_id
    @conversation.twilio_call_sid.presence ||
      @call_event.twilio_call_sid.presence ||
      "conversation-#{@conversation.id}"
  end

  def create_summary_event(call_state)
    call_state.sidecar_events.find_or_create_by!(
      conversation: @conversation,
      source: "call_summarizer",
      kind: "summary.created",
      provider: "openai_realtime",
      occurred_at: @call_event.created_at
    ) do |event|
      event.payload = {
        summary: summary_text,
        conversation_id: @conversation.id,
        call_event_id: @call_event.id
      }
      event.evidence = {
        transcript_call_event_id: @call_event.id
      }
      event.requires_review = true
    end
  end

  def create_action_draft(call_state, summary_event)
    existing = call_state.action_drafts.find_by(
      conversation: @conversation,
      kind: "follow_up_message",
      created_by: "follow_up_drafter"
    )
    return existing if existing

    call_state.action_drafts.create!(
      conversation: @conversation,
      kind: "follow_up_message",
      status: "pending_approval",
      created_by: "follow_up_drafter",
      recipient: {
        name: @conversation.customer&.name,
        phone: @conversation.customer&.phone_number
      }.compact,
      content: {
        body: draft_body,
        source_event_id: summary_event.id
      },
      approval_required: true,
      external_side_effect: {
        type: "send_message",
        executed: false
      }
    )
  end

  def create_draft_event(call_state, draft, summary_event)
    call_state.sidecar_events.find_or_create_by!(
      conversation: @conversation,
      source: "follow_up_drafter",
      kind: "action_draft.created",
      provider: "openai_realtime",
      occurred_at: draft.created_at
    ) do |event|
      event.payload = {
        action_draft_id: draft.id,
        action_kind: draft.kind,
        summary_event_id: summary_event.id
      }
      event.evidence = {
        transcript_call_event_id: @call_event.id
      }
      event.requires_review = true
    end
  end

  def summary_text
    @conversation.summary.presence ||
      @call_event.data&.dig("data", "analysis", "transcript_summary").presence ||
      "Call completed. Review the transcript for details."
  end

  def draft_body
    name = @conversation.customer&.greeting_name.presence || @conversation.customer&.name.presence
    greeting = name.present? ? "Hi #{name}," : "Hi,"

    <<~TEXT.strip
      #{greeting}

      Thanks for the call. I captured this summary for review:

      #{summary_text}

      I will follow up with next steps after reviewing the details.
    TEXT
  end
end
