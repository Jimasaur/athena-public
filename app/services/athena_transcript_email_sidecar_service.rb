class AthenaTranscriptEmailSidecarService
  def initialize(conversation:, call_event: nil)
    @conversation = conversation
    @call_event = call_event
  end

  def call
    return skipped("Conversation is required.") unless @conversation
    return skipped("Transcript email already exists.") if transcript_email_exists?

    messages = ordered_messages
    return skipped("No transcript messages found.") if messages.blank?

    recipient = transcript_recipient
    return skipped("Transcript email recipient could not be resolved.") if recipient.blank?

    payload = {
      approval_id: approval_id,
      category: "call_transcript",
      request: "Email the Athena call transcript for conversation #{@conversation.id}.",
      to: recipient,
      subject: subject,
      body: body(messages),
      mode: "approval",
      approval_workflow: true
    }

    result = GemmaMailApprovalHandoffService.new(
      conversation: @conversation,
      payload: payload
    ).call
    record_event(result, payload, messages)
    result.merge(source: "athena_transcript_email_sidecar")
  end

  private

  def approval_id
    "athena-conversation-#{@conversation.id}-transcript"
  end

  def ordered_messages
    @conversation.messages.order(:sent_at, :created_at).to_a
  end

  def transcript_recipient
    @conversation.customer&.metadata&.dig("email").to_s.strip.presence ||
      AppSetting.fetch("ATHENA_TRANSCRIPT_EMAIL_TO").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_DEFAULT_RECIPIENT").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_GMAIL_ACCOUNT").to_s.strip.presence
  end

  def subject
    caller = @conversation.customer&.name.presence ||
      @conversation.customer&.phone_number.presence ||
      "Unknown caller"
    "Athena call transcript - #{caller} - #{@conversation.created_at.strftime("%b %-d, %Y")}"
  end

  def body(messages)
    <<~TEXT.strip
      Athena call transcript

      Conversation ID: #{@conversation.id}
      Caller: #{@conversation.customer&.name.presence || "Unknown caller"}
      Phone: #{@conversation.customer&.phone_number.presence || "Unknown"}
      Status: #{@conversation.status}
      Started: #{call_started_at}

      Summary:
      #{@conversation.summary.presence || "No summary was captured."}

      Transcript:
      #{transcript_lines(messages)}
    TEXT
  end

  def call_started_at
    (@conversation.call_started_at || @conversation.created_at).in_time_zone.strftime("%Y-%m-%d %H:%M %Z")
  end

  def transcript_lines(messages)
    messages.map do |message|
      timestamp = message.sent_at&.in_time_zone&.strftime("%H:%M:%S")
      label = message.role == "assistant" ? "Athena" : "Caller"
      prefix = timestamp.present? ? "[#{timestamp}] " : ""
      "#{prefix}#{label}: #{message.content.to_s.squish}"
    end.join("\n")
  end

  def transcript_email_exists?
    @conversation.sidecar_events.where(kind: [
      "email_approval.queued",
      "email_approval.sent_to_discord",
      "email_approval.sent",
      "email_approval.cancelled",
      "transcript_email.queued"
    ]).any? { |event| event.payload.to_h["approval_id"] == approval_id }
  end

  def record_event(result, payload, messages)
    call_state = CallState.ensure_for_conversation(
      @conversation,
      provider: @conversation.call_state&.provider.presence || "openai_realtime",
      call_id: @conversation.twilio_call_sid || "conversation-#{@conversation.id}",
      status: @conversation.status.presence || "completed"
    )

    call_state.sidecar_events.create!(
      conversation: @conversation,
      source: "athena_transcript_email_sidecar",
      kind: result[:ok] ? "transcript_email.queued" : "transcript_email.failed",
      provider: "athena",
      payload: {
        ok: result[:ok],
        approval_id: payload[:approval_id],
        recipient: payload[:to],
        subject: payload[:subject],
        message_count: messages.length,
        result: result.slice(:ok, :action, :delivery_status, :error)
      }.compact,
      evidence: {
        conversation_id: @conversation.id,
        call_event_id: @call_event&.id,
        message_ids: messages.map(&:id)
      }.compact,
      changes_call_behavior: false,
      requires_review: true,
      occurred_at: Time.current
    )
  end

  def skipped(reason)
    { ok: true, skipped: true, reason: reason }
  end
end
