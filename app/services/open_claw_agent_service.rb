require "json"
require "open3"
require "shellwords"

class OpenClawAgentService
  ALLOWED_THINKING_LEVELS = %w[off minimal low medium high xhigh].freeze
  DEFAULT_TIMEOUT_SECONDS = 12

  def initialize(prompt:, agent: nil, thinking: nil, session_id: nil, profile: nil, timeout_seconds: nil, channel: nil, deliver: false, reply_channel: nil, reply_to: nil, reply_account: nil, default_session: true)
    @prompt = prompt.to_s.strip
    @agent = agent.to_s.strip.presence || AppSetting.fetch("OPENCLAW_AGENT").to_s.strip.presence || "main"
    @thinking = normalize_thinking(thinking)
    @session_id = session_id.to_s.strip.presence
    @session_id ||= AppSetting.fetch("OPENCLAW_DEFAULT_SESSION_ID").to_s.strip.presence || "athena-openclaw" if default_session
    @profile = profile.to_s.strip.presence || AppSetting.fetch("OPENCLAW_PROFILE").to_s.strip.presence
    @cli = AppSetting.fetch("OPENCLAW_CLI").to_s.strip.presence
    @cli = "openclaw" if @cli.blank? || @cli == "1"
    @timeout_seconds = normalize_timeout(timeout_seconds) ||
      normalize_timeout(AppSetting.fetch("OPENCLAW_TIMEOUT_SEC")) ||
      DEFAULT_TIMEOUT_SECONDS
    @channel = channel.to_s.strip.presence
    @deliver = truthy?(deliver)
    @reply_channel = reply_channel.to_s.strip.presence
    @reply_to = reply_to.to_s.strip.presence
    @reply_account = reply_account.to_s.strip.presence
  end

  def call
    return unavailable("Prompt is required.") if @prompt.blank?

    stdout, stderr, status = Open3.capture3(*command_execution)
    output = stdout.to_s.strip

    if status.exitstatus == 124
      return unavailable("OpenClaw request timed out after #{@timeout_seconds} seconds.", status: :gateway_timeout)
    end

    unless status.success?
      detail = stderr.to_s.strip.presence || output.presence
      return unavailable("OpenClaw request failed#{detail.present? ? ": #{detail}" : '.'}", status: :bad_gateway)
    end

    text = normalize_output(output)
    return unavailable("OpenClaw returned no reply text.", status: :bad_gateway) if text.blank?

    {
      ok: true,
      provider: "openclaw",
      agent: @agent,
      session_id: @session_id,
      channel: @channel,
      delivered: @deliver,
      reply_to: @reply_to,
      thinking: @thinking,
      reply: text,
      meta: nil
    }.compact
  rescue Errno::ENOENT
    unavailable("OpenClaw CLI not found at #{@cli}.", status: :service_unavailable)
  rescue StandardError => error
    unavailable("OpenClaw request failed: #{error.message}", status: :bad_gateway)
  end

  private

  def command_args
    args = []
    args += [ "--profile", @profile ] if @profile.present?
    args += [ "agent", "--agent", @agent ]
    args += [ "--session-id", @session_id ] if @session_id.present?
    args += [ "--channel", @channel ] if @channel.present?
    args += [ "--deliver" ] if @deliver
    args += [ "--reply-channel", @reply_channel ] if @reply_channel.present?
    args += [ "--reply-to", @reply_to ] if @reply_to.present?
    args += [ "--reply-account", @reply_account ] if @reply_account.present?
    args += [ "--message", @prompt, "--json" ]
    args += [ "--thinking", @thinking ] if @thinking.present?
    args += [ "--timeout", @timeout_seconds.to_s ] if @timeout_seconds.present?
    args
  end

  def command_execution
    [ "timeout", @timeout_seconds.to_s, @cli, *command_args ]
  end

  def normalize_output(output)
    text = output.to_s.strip
    return if text.blank?

    json_start = text.index("{")
    json_end = text.rindex("}")
    return text if json_start.blank? || json_end.blank? || json_end < json_start

    candidate = text[json_start..json_end]
    parsed = JSON.parse(candidate)
    extract_text(parsed) || fallback_text(parsed, text)
  rescue JSON::ParserError
    text
  end

  def extract_text(payload)
    return unless payload.is_a?(Hash)

    Array(payload["payloads"]).map { |entry| entry["text"].to_s.strip }.find(&:present?)
  end

  def fallback_text(payload, stdout)
    return stdout.to_s.strip if payload.blank?
    return payload.to_s.strip unless payload.is_a?(Hash)

    payload.values.map(&:to_s).map(&:strip).find(&:present?) || stdout.to_s.strip.presence
  end

  def normalize_thinking(value)
    normalized = value.to_s.strip.downcase
    normalized = AppSetting.fetch("OPENCLAW_DEFAULT_THINKING").to_s.strip.downcase if normalized.blank?
    return normalized if ALLOWED_THINKING_LEVELS.include?(normalized)

    nil
  end

  def normalize_timeout(value)
    seconds = value.to_i
    return nil if seconds <= 0

    seconds
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
