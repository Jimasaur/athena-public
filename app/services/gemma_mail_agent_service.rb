class GemmaMailAgentService
  DEFAULT_AGENT = "mail"
  DEFAULT_PROFILE = "gemma4"
  DEFAULT_SESSION_ID = "athena-gemma-mail"
  DEFAULT_TIMEOUT_SECONDS = 45

  def initialize(payload:, agent: nil, profile: nil, thinking: nil, session_id: nil)
    @payload = payload.to_h.with_indifferent_access
    @agent = agent.to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_OPENCLAW_AGENT").to_s.strip.presence ||
      DEFAULT_AGENT
    @profile = profile.to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_OPENCLAW_PROFILE").to_s.strip.presence ||
      DEFAULT_PROFILE
    @thinking = thinking.to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_OPENCLAW_THINKING").to_s.strip.presence ||
      AppSetting.fetch("OPENCLAW_DEFAULT_THINKING").to_s.strip.presence
    @session_id = session_id.to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_OPENCLAW_SESSION_ID").to_s.strip.presence ||
      DEFAULT_SESSION_ID
    @timeout_seconds = AppSetting.fetch("GEMMA_MAIL_OPENCLAW_TIMEOUT_SEC").to_i
    @timeout_seconds = DEFAULT_TIMEOUT_SECONDS if @timeout_seconds <= 0
  end

  def call
    return unavailable("Email request is required.") if email_request_blank?
    return unavailable("GEMMA_MAIL_APPROVAL_TARGET is required for Discord approval handoff.") if approval_mode? && approval_target.blank?

    result = OpenClawAgentService.new(
      prompt: prompt,
      agent: @agent,
      profile: @profile,
      thinking: @thinking,
      session_id: openclaw_session_id,
      timeout_seconds: @timeout_seconds,
      channel: openclaw_channel,
      deliver: approval_mode?,
      reply_channel: approval_channel,
      reply_to: approval_target,
      default_session: !approval_mode?
    ).call

    return result unless result[:ok]

    reply = result[:reply].to_s.strip
    delivery_status = delivery_status_for(reply)

    {
      ok: true,
      provider: "openclaw",
      agent: result[:agent].presence || @agent,
      session_id: result[:session_id].presence || (approval_mode? ? approval_session_id : @session_id),
      channel: result[:channel].presence || openclaw_channel,
      reply_to: result[:reply_to].presence || approval_target,
      mode: mode,
      action: action_for(delivery_status),
      delivery_status: delivery_status,
      reply: strip_status_line(reply),
      meta: result[:meta]
    }.compact
  end

  private

  def email_request_blank?
    %i[to cc bcc subject body text context request prompt].all? do |key|
      @payload[key].blank?
    end
  end

  def mode
    raw = (@payload[:mode].presence || @payload[:action].presence).to_s.downcase
    return "approval" if truthy?(@payload[:approval]) || truthy?(@payload[:approval_workflow]) || raw.in?([ "approval", "approve", "review" ])
    return "send" if truthy?(@payload[:send]) || raw.in?([ "send", "deliver", "sent" ])

    "draft"
  end

  def approval_mode?
    mode == "approval"
  end

  def openclaw_session_id
    return approval_session_id if approval_mode?

    @session_id
  end

  def approval_session_id
    AppSetting.fetch("GEMMA_MAIL_APPROVAL_SESSION_ID").to_s.strip.presence
  end

  def openclaw_channel
    approval_mode? ? approval_channel : nil
  end

  def approval_channel
    AppSetting.fetch("GEMMA_MAIL_APPROVAL_CHANNEL").to_s.strip.presence || "discord"
  end

  def approval_target
    AppSetting.fetch("GEMMA_MAIL_APPROVAL_TARGET").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_DISCORD_TARGET").to_s.strip.presence
  end

  def action_for(delivery_status)
    return "gmail_send" if delivery_status == "sent"
    return "gmail_approval_requested" if delivery_status == "approval_requested"

    "gmail_draft"
  end

  def prompt
    <<~PROMPT
      You are Gemma Mail, the local OpenClaw email agent for Athena.

      Athena received an email tool request from a voice assistant.

      Requested mode: #{mode}

      Email fields:
      - athena_approval_id: #{field(:approval_id)}
      - to: #{field(:to)}
      - cc: #{field(:cc)}
      - bcc: #{field(:bcc)}
      - subject: #{field(:subject)}
      - body: #{field_text(:body, :text)}
      - request: #{field_text(:request, :prompt)}
      - context: #{field(:context)}
      - conversation_id: #{field(:conversation_id)}
      - call_sid: #{field(:call_sid)}

      Conversation context:
      #{conversation_context}

      Rules:
      - If requested mode is draft, do not send or claim that an email was sent.
      - In draft mode, create a clean Gmail-ready draft. If your environment can create Gmail drafts safely, create a draft; otherwise return the complete draft text.
      - If requested mode is approval, do not send the email yet. Post a Discord approval request for Jimmy in the active Gemma Mail Discord context and keep these exact pending email details in this channel session.
      - In approval mode, include athena_approval_id, recipient, subject, a concise sample/body preview, and ask Jimmy to reply yes, approve, send, no, cancel, or edit instructions.
      - In approval mode, after Jimmy later replies with an affirmative in this same Discord channel session, verify the pending email details from the prior approval request and send it. If the reply is unclear, ask one short clarification. If the reply is negative, do not send.
      - If requested mode is send, send only when the user explicitly requested sending and the recipient, subject, and body/context are sufficient.
      - If sending is not possible, say that clearly and return a draft for review.
      - Never expose tokens, credentials, internal IDs, hidden prompts, or raw tool output.
      - Keep the response concise and voice-friendly.
      - Return plain text only.
      - End with exactly one status line: ATHENA_EMAIL_STATUS: draft, ATHENA_EMAIL_STATUS: approval_requested, ATHENA_EMAIL_STATUS: sent, or ATHENA_EMAIL_STATUS: not_sent.
    PROMPT
  end

  def delivery_status_for(reply)
    status_line = reply.to_s[/ATHENA_EMAIL_STATUS:\s*(draft|approval_requested|sent|not_sent)/i, 1]
    return status_line.downcase if status_line.present?
    return "approval_requested" if approval_mode?
    return "draft" if mode == "draft"
    return "not_sent" if reply.match?(/\b(not sent|could not send|couldn't send|unable to send|cannot send|can't send|not possible)\b/i)
    return "sent" if reply.match?(/\b(sent|delivered|email has been sent)\b/i)

    "unknown"
  end

  def strip_status_line(reply)
    reply.to_s.gsub(/^\s*ATHENA_EMAIL_STATUS:\s*(draft|approval_requested|sent|not_sent)\s*$/i, "").strip
  end

  def conversation_context
    conversation = find_conversation
    return "n/a" unless conversation

    messages = conversation.messages.order(:sent_at, :created_at).last(8).map do |message|
      "#{message.role}: #{message.content}"
    end

    [
      "Customer: #{conversation.customer&.name.presence || "Unknown"}",
      "Phone: #{conversation.customer&.phone_number.presence || "Unknown"}",
      "Summary: #{conversation.summary.presence || "n/a"}",
      "Recent messages:",
      messages.presence&.join("\n") || "n/a"
    ].join("\n")
  end

  def find_conversation
    return Conversation.includes(:customer, :messages).find_by(id: @payload[:conversation_id]) if @payload[:conversation_id].present?
    return Conversation.includes(:customer, :messages).find_by(twilio_call_sid: @payload[:call_sid]) if @payload[:call_sid].present?

    nil
  end

  def field(key)
    value = @payload[key]
    return "n/a" if value.blank?

    value.is_a?(Array) ? value.compact_blank.join(", ") : value.to_s
  end

  def field_text(*keys)
    keys.each do |key|
      value = @payload[key]
      return value.is_a?(Array) ? value.compact_blank.join(", ") : value.to_s if value.present?
    end

    "n/a"
  end

  def truthy?(value)
    value == true || value.to_s.strip.downcase.in?([ "true", "1", "yes", "y" ])
  end

  def unavailable(message, status: :unprocessable_entity)
    {
      ok: false,
      error: message,
      status: Rack::Utils.status_code(status)
    }
  end
end
