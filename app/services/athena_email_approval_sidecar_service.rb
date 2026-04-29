class AthenaEmailApprovalSidecarService
  EMAIL_INTENT = /\b(e-?mail|gmail|mail)\b/i
  APPROVAL_INTENT = /\b(approval|approve|send|sent|go ahead|sounds fine|looks good)\b/i

  def initialize(conversation:)
    @conversation = conversation
  end

  def call
    return skipped("Conversation is required.") unless @conversation
    return skipped("Email approval already exists.") if approval_exists?

    messages = ordered_messages
    return skipped("No email request found.") unless email_requested?(messages)

    payload = email_payload(messages)
    return skipped("Recipient could not be resolved.") if payload[:to].blank?
    return skipped("Body could not be resolved.") if payload[:body].blank?

    result = GemmaMailApprovalHandoffService.new(
      conversation: @conversation,
      payload: payload
    ).call
    record_detection(result, payload)
    result.merge(source: "athena_email_approval_sidecar")
  end

  private

  def ordered_messages
    @conversation.messages.order(:sent_at, :created_at).to_a
  end

  def email_requested?(messages)
    user_text = messages.select { |message| message.role == "user" }.map(&:content).join(" ")
    user_text.match?(EMAIL_INTENT) && (
      user_text.match?(APPROVAL_INTENT) ||
        user_text.match?(/\bsummary|summarize|recap|draft\b/i)
    )
  end

  def email_payload(messages)
    transcript = transcript_lines(messages)
    request_text = user_email_request(messages)
    draft = assistant_draft(messages)

    {
      request: request_text.presence || transcript,
      to: recipient_for(request_text),
      subject: subject_for(request_text, draft),
      body: body_for(messages, draft),
      mode: "approval",
      approval_workflow: true
    }.compact
  end

  def recipient_for(request_text)
    extract_email(request_text) ||
      @conversation.customer&.metadata&.dig("email").presence ||
      AppSetting.fetch("GEMMA_MAIL_DEFAULT_RECIPIENT").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_GMAIL_ACCOUNT").to_s.strip.presence
  end

  def subject_for(request_text, draft)
    extract_subject(request_text) ||
      extract_subject(draft) ||
      summary_subject
  end

  def body_for(messages, draft)
    body = extract_body(draft)
    return body if body.present?

    cleaned_draft = draft_body_without_subject_line(draft)
    return cleaned_draft if cleaned_draft.present?

    if user_email_request(messages).match?(/\b(summary|summarize|recap)\b/i)
      return summary_body(messages)
    end

    draft.presence || summary_body(messages)
  end

  def user_email_request(messages)
    messages.select { |message| message.role == "user" && message.content.match?(EMAIL_INTENT) }
      .map(&:content)
      .last
      .to_s
      .squish
  end

  def assistant_draft(messages)
    email_index = messages.rindex { |message| message.role == "user" && message.content.match?(EMAIL_INTENT) } || 0
    draft_index = messages.rindex { |message| message.role == "assistant" && message.content.match?(/\b(draft|subject|body)\b/i) }
    approval_index = messages.rindex { |message| message.role == "user" && message.content.match?(APPROVAL_INTENT) } || messages.length
    start_index = [ draft_index || email_index, email_index ].min
    window = messages[start_index..approval_index] || []
    draft_lines = window.select { |message| message.role == "assistant" }.map { |message| message.content.to_s.squish }
    draft_lines.join("\n").presence
  end

  def summary_body(messages)
    <<~TEXT.strip
      Athena call summary:

      #{transcript_lines(messages)}
    TEXT
  end

  def transcript_lines(messages)
    messages.map do |message|
      label = message.role == "assistant" ? "Athena" : "Caller"
      "#{label}: #{message.content.to_s.squish}"
    end.join("\n")
  end

  def extract_email(text)
    text.to_s[/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i]
  end

  def extract_subject(text)
    text.to_s[/\bsubject[:\s]+(.+?)(?:\n|\bbody\b|[.?!]\s*\z|\z)/i, 1]&.strip&.delete_suffix("\"")&.delete_suffix("”")&.presence
  end

  def extract_body(text)
    text.to_s[/\bbody[:\s]+(.+)\z/im, 1]&.strip&.presence
  end

  def draft_body_without_subject_line(text)
    lines = text.to_s.lines.map(&:squish).reject(&:blank?)
    lines.reject! { |line| line.match?(/\b(draft\s+)?subject\b/i) }
    lines.join("\n").presence
  end

  def summary_subject
    "Athena call summary - #{@conversation.created_at.strftime("%b %-d, %Y")}"
  end

  def approval_exists?
    approval_id = "athena-conversation-#{@conversation.id}"
    @conversation.sidecar_events.where(kind: [
      "email_approval.queued",
      "email_approval.sent_to_discord",
      "email_approval.sent"
    ]).any? { |event| event.payload.to_h["approval_id"] == approval_id }
  end

  def record_detection(result, payload)
    call_state = CallState.ensure_for_conversation(
      @conversation,
      provider: @conversation.call_state&.provider.presence || "openai_realtime",
      call_id: @conversation.twilio_call_sid || "conversation-#{@conversation.id}",
      status: @conversation.status == "completed" ? "completed" : "active"
    )

    call_state.sidecar_events.create!(
      conversation: @conversation,
      source: "athena_email_approval_sidecar",
      kind: "email_approval.auto_detected",
      provider: "athena",
      payload: {
        ok: result[:ok],
        recipient: payload[:to],
        subject: payload[:subject],
        body_preview: payload[:body].to_s.truncate(240),
        result: result.slice(:ok, :action, :delivery_status, :error)
      }.compact,
      evidence: {
        conversation_id: @conversation.id,
        message_ids: ordered_messages.map(&:id)
      },
      changes_call_behavior: false,
      requires_review: true,
      occurred_at: Time.current
    )
  end

  def skipped(reason)
    { ok: true, skipped: true, reason: reason }
  end
end
