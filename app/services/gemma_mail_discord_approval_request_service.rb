require "json"
require "open3"

class GemmaMailDiscordApprovalRequestService
  CommandResult = Struct.new(:stdout, :stderr, :exitstatus, keyword_init: true) do
    def success?
      exitstatus.to_i == 0
    end
  end

  DEFAULT_PROFILE = "gemma4"
  DEFAULT_CHANNEL = "discord"
  DEFAULT_TIMEOUT_SECONDS = 30

  def initialize(payload:, profile: nil, channel: nil, target: nil, timeout_seconds: nil, openclaw_cli: nil, runner: nil)
    @payload = payload.to_h.with_indifferent_access
    @profile = profile.to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_OPENCLAW_PROFILE").to_s.strip.presence ||
      DEFAULT_PROFILE
    @channel = channel.to_s.strip.presence ||
      AppSetting.fetch("ATHENA_APPROVAL_CHANNEL").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_APPROVAL_CHANNEL").to_s.strip.presence ||
      DEFAULT_CHANNEL
    @target = target.to_s.strip.presence ||
      AppSetting.fetch("ATHENA_APPROVAL_TARGET").to_s.strip.presence ||
      AppSetting.fetch("ATHENA_DISCORD_APPROVAL_TARGET").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_APPROVAL_TARGET").to_s.strip.presence ||
      AppSetting.fetch("GEMMA_MAIL_DISCORD_TARGET").to_s.strip.presence
    @timeout_seconds = timeout_seconds.to_i.positive? ? timeout_seconds.to_i : DEFAULT_TIMEOUT_SECONDS
    @openclaw_cli = normalize_openclaw_cli(openclaw_cli)
    @runner = runner || method(:capture_command)
  end

  def call
    return unavailable("GEMMA_MAIL_APPROVAL_TARGET is required for Discord approval handoff.") if @target.blank?
    return unavailable("Email recipient is required.") if field(:to).blank?
    return unavailable("Email subject is required.") if field(:subject).blank?
    return unavailable("Email body is required.") if field(:body).blank?

    result = run(
      @openclaw_cli,
      "--profile", @profile,
      "message", "send",
      "--channel", @channel,
      "--target", @target,
      "--message", approval_message,
      "--json"
    )
    return command_error("Discord approval request failed", result) unless result.success?

    {
      ok: true,
      provider: "openclaw",
      channel: @channel,
      reply_to: @target,
      mode: "approval",
      action: "gmail_approval_requested",
      delivery_status: "approval_requested",
      reply: message_id_from(result.stdout) || "approval_posted"
    }
  end

  private

  def approval_message
    <<~TEXT
      Approval request for Jimmy:

      Email awaiting your approval:
      - **Approval ID:** #{approval_id}
      - **To:** #{field(:to)}
      - **Subject:** #{field(:subject)}
      - **Body preview:** #{body_preview}

      Please reply with one of:
      - **yes / approve / send / proceed** -> I'll send it now
      - **no / cancel** -> I'll discard it
      - **edit** -> Tell me what to change

      ATHENA_EMAIL_STATUS: approval_requested
    TEXT
  end

  def normalize_openclaw_cli(value)
    cli = value.to_s.strip.presence || AppSetting.fetch("OPENCLAW_CLI").to_s.strip.presence
    return "openclaw" if cli.blank? || cli == "1"

    cli
  end

  def approval_id
    field(:approval_id).presence || "athena-conversation-#{field(:conversation_id)}"
  end

  def body_preview
    text = field(:body).to_s.gsub(/\s+/, " ").strip
    return text if text.length <= 700

    "#{text[0, 697]}..."
  end

  def field(key)
    value = @payload[key]
    return if value.blank?

    value.to_s.strip
  end

  def message_id_from(output)
    parsed = parse_json(output)
    parsed.dig("payload", "id") ||
      parsed.dig("payload", "message", "id") ||
      parsed.dig("payload", "messages", 0, "id") ||
      parsed["id"]
  rescue JSON::ParserError
    nil
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
