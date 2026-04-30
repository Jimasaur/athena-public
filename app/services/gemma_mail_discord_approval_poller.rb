require "json"
require "open3"

class GemmaMailDiscordApprovalPoller
  CommandResult = Struct.new(:stdout, :stderr, :exitstatus, keyword_init: true) do
    def success?
      exitstatus.to_i == 0
    end
  end

  Approval = Struct.new(:approval_id, :to, :subject, :body, :message_id, :timestamp_ms, keyword_init: true)
  Response = Struct.new(:kind, :content, :message_id, :timestamp_ms, :edits, :author_id, :reply_to_message_id, :approval_id, keyword_init: true)

  DEFAULT_LIMIT = 30
  DEFAULT_TIMEOUT_SECONDS = 45
  TERMINAL_KINDS = %w[
    email_approval.sent
    email_approval.cancelled
  ].freeze

  def initialize(profile: nil, channel: nil, target: nil, account: nil, limit: nil, timeout_seconds: nil, openclaw_cli: nil, runner: nil)
    @profile = profile.to_s.strip.presence || AppSetting.fetch("GEMMA_MAIL_OPENCLAW_PROFILE").to_s.strip.presence || "gemma4"
    @channel = channel.to_s.strip.presence || AppSetting.fetch("ATHENA_APPROVAL_CHANNEL").to_s.strip.presence || AppSetting.fetch("GEMMA_MAIL_APPROVAL_CHANNEL").to_s.strip.presence || "discord"
    @target = target.to_s.strip.presence || AppSetting.fetch("ATHENA_APPROVAL_TARGET").to_s.strip.presence || AppSetting.fetch("ATHENA_DISCORD_APPROVAL_TARGET").to_s.strip.presence || AppSetting.fetch("GEMMA_MAIL_APPROVAL_TARGET").to_s.strip.presence
    @account = account.to_s.strip.presence || AppSetting.fetch("GEMMA_MAIL_GMAIL_ACCOUNT").to_s.strip.presence || "demo@example.com"
    @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
    @timeout_seconds = timeout_seconds.to_i.positive? ? timeout_seconds.to_i : DEFAULT_TIMEOUT_SECONDS
    @openclaw_cli = normalize_openclaw_cli(openclaw_cli)
    @runner = runner || method(:capture_command)
  end

  def call
    return unavailable("GEMMA_MAIL_APPROVAL_TARGET is required.") if @target.blank?
    return unavailable("ATHENA_APPROVAL_DISCORD_APPROVER_IDS is required.") if allowed_approver_ids.blank?

    read_result = read_messages
    return read_result unless read_result[:ok]

    processed = process_messages(read_result[:messages])

    {
      ok: true,
      checked: read_result[:messages].size,
      processed: processed
    }
  end

  private

  def normalize_openclaw_cli(value)
    cli = value.to_s.strip.presence || AppSetting.fetch("OPENCLAW_CLI").to_s.strip.presence
    return "openclaw" if cli.blank? || cli == "1"

    cli
  end

  def read_messages
    result = run(
      @openclaw_cli,
      "--profile", @profile,
      "message", "read",
      "--channel", @channel,
      "--target", @target,
      "--limit", @limit.to_s,
      "--json"
    )
    return command_error("Discord approval read failed", result) unless result.success?

    payload = parse_json(result.stdout)
    messages = payload.dig("payload", "messages")
    return unavailable("Discord approval read returned no messages.") unless messages.is_a?(Array)

    { ok: true, messages: messages }
  end

  def process_messages(messages)
    approvals_by_id = {}
    approvals_by_message_id = {}
    processed = []

    messages.sort_by { |message| message["timestampMs"].to_i }.each do |message|
      approval = parse_approval(message)
      if approval
        unless terminal_approval?(approval.approval_id) || superseded_approval_message?(approval)
          approvals_by_id[approval.approval_id] = approval
          approvals_by_message_id[approval.message_id] = approval
        end
        next
      end
      if (prompt_approval_id = clarification_prompt_approval_id(message))
        approvals_by_message_id[message["id"].to_s] = approvals_by_id[prompt_approval_id] if approvals_by_id[prompt_approval_id]
        next
      end

      response = parse_response(message)
      next unless response

      current_approval = approval_for_response(response, approvals_by_id, approvals_by_message_id)
      next unless current_approval
      next if response.timestamp_ms <= current_approval.timestamp_ms
      next if processed_reply?(response.message_id)

      result = process_response(current_approval, response)
      processed << result if result
    end

    processed
  end

  def process_response(approval, response)
    conversation = conversation_for(approval.approval_id)
    return unless conversation

    conversation.with_lock do
      return if terminal_approval?(approval.approval_id) || processed_reply?(response.message_id)

      process_response_without_lock(approval, response)
    end
  end

  def process_response_without_lock(approval, response)
    case response.kind
    when :approve
      record_event("email_approval.discord_approved", approval, response, requires_review: false)
      send_result = send_email(approval)

      if send_result[:ok]
        record_event("email_approval.sent", approval, response, result: send_result, requires_review: false)
        post_discord("Athena approval #{approval.approval_id}: Sent to #{approval.to}.", reply_to: response.message_id)
      else
        record_event("email_approval.send_failed", approval, response, result: send_result, requires_review: true)
        post_discord("Athena approval #{approval.approval_id}: I could not send it. #{send_result[:error]}", reply_to: response.message_id)
      end

      { approval_id: approval.approval_id, action: "send", ok: send_result[:ok] }
    when :cancel
      record_event("email_approval.cancelled", approval, response, requires_review: false)
      post_discord("Athena approval #{approval.approval_id}: cancelled.", reply_to: response.message_id)
      { approval_id: approval.approval_id, action: "cancel", ok: true }
    when :edit
      edits = edit_instructions(response.content, approval)
      if edits.present?
        edited_approval = approval_with_edits(approval, edits)
        record_event("email_approval.edited", edited_approval, response, result: { ok: true, edits: edits }, requires_review: false)
        post_result = post_approval_request(edited_approval, response)
        record_event("email_approval.sent_to_discord", edited_approval, response, result: post_result, requires_review: !post_result[:ok])
        { approval_id: approval.approval_id, action: "edit", ok: post_result[:ok], edits: edits }
      else
        record_event("email_approval.edit_requested", approval, response, requires_review: true)
        post_discord("Athena approval #{approval.approval_id}: what should I change?", reply_to: response.message_id)
        { approval_id: approval.approval_id, action: "edit", ok: true }
      end
    end
  end

  def approval_with_edits(approval, edits)
    Approval.new(
      approval_id: approval.approval_id,
      to: edits[:to].presence || approval.to,
      subject: edits[:subject].presence || approval.subject,
      body: edits[:body].presence || approval.body,
      message_id: approval.message_id,
      timestamp_ms: approval.timestamp_ms
    )
  end

  def post_approval_request(approval, response)
    result = GemmaMailDiscordApprovalRequestService.new(
      payload: {
        approval_id: approval.approval_id,
        to: approval.to,
        subject: approval.subject,
        body: approval.body
      },
      profile: @profile,
      channel: @channel,
      target: @target,
      openclaw_cli: @openclaw_cli,
      runner: @runner
    ).call

    post_discord("Athena approval #{approval.approval_id}: updated; please approve the revised email.", reply_to: response.message_id) if result[:ok]
    result
  end

  def send_email(approval)
    body_arg = approval.body.to_s.gsub("\\", "\\\\").gsub("\r\n", "\n").gsub("\r", "\n").gsub("\n", "\\n")
    result = run(
      "gemma-mail-gog",
      "send",
      "--confirmed",
      "--to", approval.to,
      "--subject", approval.subject,
      "--body-escaped", body_arg,
      "--account", @account,
      "--plain"
    )

    return command_error("Gemma Mail send failed", result) unless result.success?

    { ok: true, stdout: result.stdout.to_s.strip.presence }
  end

  def post_discord(message, reply_to: nil)
    args = [
      @openclaw_cli,
      "--profile", @profile,
      "message", "send",
      "--channel", @channel,
      "--target", @target,
      "--message", message,
      "--json"
    ]
    args += [ "--reply-to", reply_to ] if reply_to.present?

    result = run(*args)
    result.success?
  end

  def parse_approval(message)
    return if human_message?(message)

    content = message["content"].to_s
    return unless content.include?("Approval ID:")

    approval_id = extract_field(content, "Approval ID")
    visible_to = extract_field(content, "To")
    visible_subject = extract_field(content, "Subject")
    stored = stored_approval_payload(approval_id, visible_subject: visible_subject, message_id: message["id"])
    to = visible_to.presence || stored["recipient"].presence
    subject = visible_subject.presence || stored["subject"].presence
    body = stored["body"].presence || extract_field(content, "Body") || extract_field(content, "Body preview")
    return if approval_id.blank? || to.blank? || subject.blank? || body.blank?

    Approval.new(
      approval_id: approval_id,
      to: to,
      subject: subject,
      body: body,
      message_id: message["id"].to_s,
      timestamp_ms: message["timestampMs"].to_i
    )
  end

  def parse_response(message)
    return unless human_message?(message)
    author_id = message.dig("author", "id").to_s
    return unless allowed_approver_ids.include?(author_id)

    content = message["content"].to_s.strip
    normalized = content.downcase.gsub(/[[:punct:]]+\z/, "").strip
    approval_id = extract_approval_id(content)
    kind =
      if normalized.match?(/\b(yes|y|approve|approved|send|send it|go ahead|do it|proceed)\b/)
        :approve
      elsif normalized.match?(/\b(no|n|cancel|discard|stop)\b/)
        :cancel
      elsif normalized.match?(/\Aedit\b/) || edit_instruction?(content)
        :edit
      end
    return unless kind

    Response.new(
      kind: kind,
      content: content,
      message_id: message["id"].to_s,
      timestamp_ms: message["timestampMs"].to_i,
      edits: nil,
      author_id: author_id,
      reply_to_message_id: reply_to_message_id(message),
      approval_id: approval_id
    )
  end

  def edit_instructions(content, approval = nil)
    text = content.to_s.strip
    edits = {}

    remove_match = text.match(/\bsubject\b.*\bremove\s+(?:the\s+)?(.+?)\s+from\s+["“]?(.+?)["”]?\s*\z/i)
    if remove_match
      needle = normalize_remove_token(remove_match[1])
      phrase = remove_match[2].strip
      replacement = needle == "_" ? " " : ""
      edited_phrase = phrase.gsub(needle, replacement).squish
      current_subject = approval&.subject.to_s
      edits[:subject] = current_subject.include?(phrase) ? current_subject.sub(phrase, edited_phrase).squish : edited_phrase
    end

    if edits[:subject].blank? && text.match?(/\bsubject\b.*\bremove\s+(?:the\s+)?(?:underscore|_)\b/i)
      current_subject = approval&.subject.to_s
      edits[:subject] = current_subject.gsub("_", " ").squish if current_subject.present?
    end

    subject = text[/\b(?:edit|change|update)\s+(?:the\s+)?subject\s+(?:to say|to|as)\s+["“]?(.+?)["”]?\s*\z/i, 1]
    subject ||= text[/\b(?:edit|change|update)\s+(?:the\s+)?subject\s*[:=]\s*["“]?(.+?)["”]?\s*\z/i, 1]
    subject ||= text[/\b(?:the\s+)?subject\s+(?:should be|is|to say|to|as)\s*:?\s*["“]?(.+?)["”]?\s*\z/i, 1]
    edits[:subject] = subject.strip if subject.present? && edits[:subject].blank?

    to = text[/\b(?:edit|change|update)\s+(?:the\s+)?(?:to|recipient)\s+(?:to|as)\s+([^\s]+@[^\s]+)\s*\z/i, 1]
    to ||= text[/\b(?:edit|change|update)\s+(?:the\s+)?(?:to|recipient)\s*[:=]\s*([^\s]+@[^\s]+)\s*\z/i, 1]
    to ||= text[/\b(?:the\s+)?(?:recipient|to)\s+(?:should be|is|to|as)\s*:?\s*([^\s]+@[^\s]+)\s*\z/i, 1]
    edits[:to] = to.strip if to.present?

    body = text[/\b(?:edit|change|update)\s+(?:the\s+)?body\s+(?:to say|to|as)\s+["“]?(.+?)["”]?\s*\z/im, 1]
    body ||= text[/\b(?:edit|change|update)\s+(?:the\s+)?body\s*[:=]\s*["“]?(.+?)["”]?\s*\z/im, 1]
    body ||= text[/\b(?:the\s+)?body\s+(?:should be|is|to say|to|as)\s*:?\s*["“]?(.+?)["”]?\s*\z/im, 1]
    edits[:body] = body.strip if body.present?

    edits
  end

  def edit_instruction?(content)
    content.to_s.match?(/\b(subject|body|recipient|to)\b\s*(?:[:=]|(?:should be|is|to say|to|as)\b)/i)
  end

  def normalize_remove_token(token)
    normalized = token.to_s.strip.delete_prefix("\"").delete_suffix("\"").delete_prefix("“").delete_suffix("”")
    return "_" if normalized.match?(/\A(?:_|underscore)\z/i)

    normalized
  end

  def extract_field(content, label)
    content.each_line do |line|
      cleaned = line.to_s.strip.sub(/\A[-*]\s*/, "").gsub("**", "")
      match = cleaned.match(/\A#{Regexp.escape(label)}:\s*(.+)\z/i)
      return match[1].strip.presence if match
    end

    nil
  end

  def stored_approval_payload(approval_id, visible_subject: nil, message_id: nil)
    _visible_subject = visible_subject
    return {} if approval_id.blank?

    candidates = SidecarEvent.where(kind: %w[
      email_approval.queued
      email_approval.sent_to_discord
    ]).order(created_at: :desc).select do |event|
      event.payload.to_h["approval_id"] == approval_id
    end

    matched_by_message = candidates.find do |event|
      payload = event.payload.to_h
      payload["discord_approval_message_id"] == message_id ||
        payload.dig("result", "reply") == message_id
    end
    return matched_by_message.payload.to_h if matched_by_message

    candidates.first&.payload.to_h || {}
  end

  def human_message?(message)
    !message.dig("author", "bot")
  end

  def approval_for_response(response, approvals_by_id, approvals_by_message_id)
    return approvals_by_message_id[response.reply_to_message_id] if response.reply_to_message_id.present?
    return approvals_by_id[response.approval_id] if response.approval_id.present?

    nil
  end

  def reply_to_message_id(message)
    message["replyTo"].presence ||
      message["reply_to"].presence ||
      message.dig("referencedMessage", "id").presence ||
      message.dig("referenced_message", "id").presence ||
      message.dig("messageReference", "messageId").presence ||
      message.dig("message_reference", "message_id").presence
  end

  def extract_approval_id(content)
    content.to_s[/\bathena-conversation-\d+(?:-[A-Za-z0-9_]+)*\b/, 0]
  end

  def clarification_prompt_approval_id(message)
    return unless message.dig("author", "bot")

    message["content"].to_s[/\bAthena approval (athena-conversation-\d+(?:-[A-Za-z0-9_]+)*): what should I change\?/i, 1]
  end

  def allowed_approver_ids
    @allowed_approver_ids ||= AppSetting.fetch("ATHENA_APPROVAL_DISCORD_APPROVER_IDS").to_s.split(/[,\s]+/).reject(&:blank?)
  end

  def superseded_approval_message?(approval)
    SidecarEvent.where(kind: "email_approval.sent_to_discord").any? do |event|
      payload = event.payload.to_h
      payload["approval_id"] == approval.approval_id &&
        payload["discord_approval_message_id"].present? &&
        payload["discord_approval_message_id"] != approval.message_id
    end
  end

  def terminal_approval?(approval_id)
    SidecarEvent.where(kind: TERMINAL_KINDS).any? do |event|
      event.payload.to_h["approval_id"] == approval_id
    end
  end

  def processed_reply?(message_id)
    return true if message_id.blank?

    SidecarEvent.where(kind: %w[
      email_approval.discord_approved
      email_approval.cancelled
      email_approval.edited
      email_approval.edit_requested
      email_approval.send_failed
      email_approval.sent
    ]).any? do |event|
      event.payload.to_h["discord_response_message_id"] == message_id
    end
  end

  def record_event(kind, approval, response, result: nil, requires_review:)
    conversation = conversation_for(approval.approval_id)
    return unless conversation

    call_state = CallState.ensure_for_conversation(
      conversation,
      provider: conversation.call_state&.provider.presence || "openai_realtime",
      call_id: conversation.twilio_call_sid || "conversation-#{conversation.id}",
      status: conversation.status == "completed" ? "completed" : "active"
    )

    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "gemma_mail_discord_approval_poller",
      kind: kind,
      provider: "gemma-mail-gog",
      payload: {
        approval_id: approval.approval_id,
        recipient: approval.to,
        subject: approval.subject,
        body: approval.body,
        discord_approval_message_id: discord_approval_message_id_for(kind, approval, result),
        superseded_discord_approval_message_id: superseded_discord_approval_message_id_for(kind, approval, result),
        discord_response_message_id: response.message_id,
        discord_response: response.content,
        result: result
      }.compact,
      evidence: {
        conversation_id: conversation.id
      },
      changes_call_behavior: false,
      requires_review: requires_review,
      occurred_at: Time.current
    )
  end

  def conversation_for(approval_id)
    conversation_id = approval_id.to_s[/\Aathena-conversation-(\d+)(?:-.+)?\z/, 1]
    Conversation.find_by(id: conversation_id) if conversation_id
  end

  def discord_approval_message_id_for(kind, approval, result)
    return result.to_h[:reply].presence || approval.message_id if kind == "email_approval.sent_to_discord"

    approval.message_id
  end

  def superseded_discord_approval_message_id_for(kind, approval, result)
    return unless kind == "email_approval.sent_to_discord"
    return unless result.to_h[:reply].present?

    approval.message_id
  end

  def parse_json(output)
    text = output.to_s.strip
    JSON.parse(text)
  rescue JSON::ParserError
    json_start = text.index("{")
    json_end = text.rindex("}")
    raise if json_start.blank? || json_end.blank? || json_end < json_start

    JSON.parse(text[json_start..json_end])
  end

  def run(*args)
    @runner.call(*args)
  end

  def capture_command(*args)
    stdout, stderr, status = Open3.capture3("timeout", @timeout_seconds.to_s, *args)
    CommandResult.new(stdout: stdout, stderr: stderr, exitstatus: status.exitstatus)
  end

  def command_error(prefix, result)
    detail = result.stderr.to_s.strip.presence || result.stdout.to_s.strip.presence || "exit #{result.exitstatus}"
    { ok: false, error: "#{prefix}: #{detail}" }
  end

  def unavailable(message)
    { ok: false, error: message }
  end
end
