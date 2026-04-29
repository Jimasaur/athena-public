class GemmaMailApprovalHandoffService
  def initialize(conversation:, payload:)
    @conversation = conversation
    @payload = payload.to_h.with_indifferent_access
  end

  def call
    return unavailable("Conversation is required for Gemma Mail approval handoff.") unless @conversation

    payload = normalized_payload
    return unavailable("Email recipient is required.") if payload[:to].blank?
    return unavailable("Email body is required.") if payload[:body].blank?
    return unavailable("GEMMA_MAIL_APPROVAL_TARGET is required for Discord approval handoff.") if approval_target.blank?

    call_state = ensure_call_state
    create_queued_event(call_state, payload)
    GemmaMailApprovalJob.perform_later(call_state.id, payload)

    {
      ok: true,
      provider: "athena",
      action: "gmail_approval_requested",
      mode: "approval",
      delivery_status: "approval_requested",
      reply: "I sent that to Gemma Mail for Discord approval. It has not been sent yet.",
      recipient: payload[:to],
      subject: payload[:subject]
    }
  end

  private

  def normalized_payload
    request_text = @payload[:request].to_s.strip
    to = @payload[:to].presence || extract_email(request_text) || conversation_default_email
    subject = @payload[:subject].presence || extract_labeled_value(request_text, "subject") || "Follow-up"
    body = @payload[:body].presence || @payload[:text].presence || @payload[:context].presence || extract_labeled_value(request_text, "body") || request_text.presence

    @payload.merge(
      approval_id: approval_id,
      to: to,
      subject: subject,
      body: body,
      request: request_text.presence,
      conversation_id: @conversation.id,
      call_sid: @conversation.twilio_call_sid,
      category: @payload[:category].presence,
      approval_channel: approval_channel,
      approval_target: approval_target,
      mode: "approval",
      approval_workflow: true
    ).compact
  end

  def ensure_call_state
    CallState.ensure_for_conversation(
      @conversation,
      provider: @conversation.call_state&.provider.presence || "openai_realtime",
      call_id: @conversation.twilio_call_sid || "conversation-#{@conversation.id}",
      status: @conversation.status == "completed" ? "completed" : "active"
    )
  end

  def create_queued_event(call_state, payload)
    call_state.sidecar_events.create!(
      conversation: @conversation,
      source: "agent_tool",
      kind: "email_approval.queued",
      provider: "athena",
      payload: {
        recipient: payload[:to],
        subject: payload[:subject],
        body: payload[:body],
        request: payload[:request],
        approval_id: payload[:approval_id],
        category: payload[:category],
        approval_channel: approval_channel,
        approval_target: approval_target
      }.compact,
      evidence: {
        conversation_id: @conversation.id
      },
      changes_call_behavior: false,
      requires_review: true,
      occurred_at: Time.current
    )
  end

  def approval_channel
    AppSetting.fetch("ATHENA_APPROVAL_CHANNEL").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_APPROVAL_CHANNEL").to_s.strip.presence ||
      "discord"
  end

  def approval_target
    AppSetting.fetch("ATHENA_APPROVAL_TARGET").to_s.strip.presence ||
      AppSetting.fetch("ATHENA_DISCORD_APPROVAL_TARGET").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_APPROVAL_TARGET").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_DISCORD_TARGET").to_s.strip.presence
  end

  def approval_id
    @payload[:approval_id].presence || "athena-conversation-#{@conversation.id}"
  end

  def extract_email(text)
    text.to_s[/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i]
  end

  def conversation_default_email
    @conversation.customer&.metadata&.dig("email").to_s.strip.presence
  end

  def extract_labeled_value(text, label)
    quoted = text.to_s.match(/#{Regexp.escape(label)}\s+["“]([^"”]+)["”]/i)
    return quoted[1].strip.presence if quoted

    match = text.to_s.match(/#{Regexp.escape(label)}\s+["“]?(.+?)(?:["”]?\s+(?:and\s+)?(?:subject|body)\b|["”]?[.?!]?\z)/i)
    match&.[](1)&.strip&.delete_suffix("\"")&.delete_suffix("”")&.presence
  end

  def unavailable(message)
    {
      ok: false,
      error: message,
      status: 422
    }
  end
end
