class AthenaIdeaCaptureService
  def initialize(conversation:, call_event: nil, payload: {})
    @conversation = conversation
    @call_event = call_event
    @payload = payload.to_h.with_indifferent_access
  end

  def call
    return unavailable("Conversation is required.") unless @conversation

    idea = upsert_idea_capture
    call_state = ensure_call_state
    create_capture_event(call_state, idea)
    report_result = AthenaIdeaDiscordReportService.new(idea_capture: idea).call
    create_report_event(call_state, idea, report_result)

    {
      ok: true,
      command: "capture_idea",
      action: "idea_captured",
      idea_capture_id: idea.id,
      title: idea.title,
      category: idea.category,
      reply: "I captured that idea for the rev cycle retreat review."
    }
  end

  private

  def upsert_idea_capture
    idea = @conversation.idea_captures.order(:created_at).first || @conversation.idea_captures.build
    idea.assign_attributes(idea_attributes)
    idea.save!
    idea
  end

  def idea_attributes
    {
      title: field(:title).presence || generated_title,
      category: field(:category).presence || classified_category,
      department: field(:department).presence || field(:area).presence || "Revenue Cycle",
      status: "captured",
      problem: field(:problem).presence || extracted_problem,
      proposed_solution: field(:proposed_solution).presence || field(:solution).presence || extracted_solution,
      impact: field(:impact).presence || extracted_impact,
      next_step: field(:next_step).presence || "Review, score, and assign an owner during the rev cycle retreat.",
      payload: idea_payload
    }
  end

  def idea_payload
    {
      source: @payload[:source].presence || "athena_call",
      request: field(:request),
      caller: {
        name: @conversation.customer&.name,
        phone: @conversation.customer&.phone_number
      }.compact,
      transcript: transcript_lines,
      workshop_prompt: "What would need to be true to pilot this safely in 30-60 days?",
      captured_at: Time.current.utc.iso8601
    }.compact
  end

  def ensure_call_state
    CallState.ensure_for_conversation(
      @conversation,
      provider: @conversation.call_state&.provider.presence || "openai_realtime",
      call_id: @conversation.twilio_call_sid || "conversation-#{@conversation.id}",
      status: @conversation.status == "completed" ? "completed" : "active",
      use_case_slug: "rev-cycle-ideation-session",
      space: "healthcare"
    )
  end

  def create_capture_event(call_state, idea)
    call_state.sidecar_events.create!(
      conversation: @conversation,
      source: "athena_idea_capture",
      kind: "idea_capture.captured",
      provider: "athena",
      payload: idea_payload_for_event(idea),
      evidence: {
        conversation_id: @conversation.id,
        call_event_id: @call_event&.id,
        message_ids: @conversation.messages.order(:sent_at, :created_at).pluck(:id)
      }.compact,
      changes_call_behavior: false,
      requires_review: true,
      occurred_at: Time.current
    )
  end

  def create_report_event(call_state, idea, result)
    call_state.sidecar_events.create!(
      conversation: @conversation,
      source: "athena_idea_reporter",
      kind: result[:ok] ? "idea_capture.reported" : "idea_capture.report_failed",
      provider: result[:provider].presence || "athena",
      payload: idea_payload_for_event(idea).merge(result: result.slice(:ok, :provider, :channel, :target, :skipped, :error)),
      evidence: {
        conversation_id: @conversation.id,
        idea_capture_id: idea.id
      },
      changes_call_behavior: false,
      requires_review: !result[:ok],
      occurred_at: Time.current
    )
  end

  def idea_payload_for_event(idea)
    {
      idea_capture_id: idea.id,
      title: idea.title,
      category: idea.category,
      department: idea.department,
      impact: idea.impact,
      next_step: idea.next_step
    }.compact
  end

  def field(key)
    value = @payload[key]
    value.is_a?(Array) ? value.compact_blank.join(", ") : value.to_s.squish.presence
  end

  def generated_title
    seed = field(:request).presence || user_text.presence || @conversation.summary.presence
    return "Rev cycle improvement idea" if seed.blank?

    "Rev cycle idea: #{seed.squish.truncate(72)}"
  end

  def classified_category
    text = combined_text.downcase
    return "Denials and Claims" if text.match?(/\b(denial|denials|claim|claims|appeal|underpayment)\b/)
    return "Prior Authorization" if text.match?(/\b(prior auth|authorization|auth)\b/)
    return "Patient Access" if text.match?(/\b(registration|scheduling|eligibility|front desk|intake)\b/)
    return "Coding and Documentation" if text.match?(/\b(coding|cdi|documentation|charge capture)\b/)
    return "Automation" if text.match?(/\b(automation|bot|agent|ai|rpa|workflow)\b/)
    return "Cost Savings" if text.match?(/\b(cost|savings|reduce|manual work|staff time|fte)\b/)

    "Revenue Cycle Improvement"
  end

  def extracted_problem
    return field(:request) if field(:request).present?
    return @conversation.summary if @conversation.summary.present?
    return user_messages.first.content.to_s.squish if user_messages.any?

    "The caller discussed a revenue cycle improvement opportunity."
  end

  def extracted_solution
    solution = user_messages.map(&:content).find { |content| content.match?(/\b(should|could|automate|build|use|create|route|send|flag)\b/i) }
    solution.to_s.squish.presence || "Clarify the proposed workflow or automation during retreat review."
  end

  def extracted_impact
    text = combined_text
    return "Potential cost savings or staff time reduction." if text.match?(/\b(cost|savings|manual work|staff time|fte|reduce)\b/i)
    return "Potential revenue capture, denial prevention, or faster resolution." if text.match?(/\b(denial|claim|revenue|payment|cash|appeal)\b/i)

    "Potential operational improvement for revenue cycle teams."
  end

  def transcript_lines
    @conversation.messages.order(:sent_at, :created_at).map do |message|
      label = message.role == "assistant" ? "Athena" : "Caller"
      "#{label}: #{message.content.to_s.squish}"
    end
  end

  def user_messages
    @conversation.messages.order(:sent_at, :created_at).select { |message| message.role == "user" }
  end

  def user_text
    user_messages.map(&:content).join(" ").squish
  end

  def combined_text
    [ field(:request), @conversation.summary, user_text ].compact_blank.join(" ")
  end

  def unavailable(message)
    { ok: false, command: "capture_idea", error: message, status: 422 }
  end
end
