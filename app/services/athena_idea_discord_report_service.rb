require "json"
require "open3"

class AthenaIdeaDiscordReportService
  CommandResult = Struct.new(:stdout, :stderr, :exitstatus, keyword_init: true) do
    def success?
      exitstatus.to_i == 0
    end
  end

  def initialize(idea_capture:, runner: nil)
    @idea_capture = idea_capture
    @runner = runner || method(:capture_command)
  end

  def call
    return post_webhook if webhook_url.present?
    return post_openclaw if discord_target.present?

    { ok: false, skipped: true, error: "Athena Discord reporting is not configured." }
  end

  private

  def post_webhook
    result = DiscordWebhookService.new(
      url: webhook_url,
      username: discord_username
    ).post(
      content: "Athena captured a rev cycle idea: #{@idea_capture.title}",
      embeds: [ embed ]
    )

    result.merge(provider: "discord_webhook")
  end

  def post_openclaw
    result = run(
      openclaw_cli,
      "--profile", openclaw_profile,
      "message", "send",
      "--channel", discord_channel,
      "--target", discord_target,
      "--message", openclaw_message,
      "--json"
    )
    return command_error(result) unless result.success?

    { ok: true, provider: "openclaw", channel: discord_channel, target: discord_target, reply: message_id_from(result.stdout) || "posted" }
  end

  def embed
    {
      title: @idea_capture.title,
      description: @idea_capture.problem.to_s.tr("\n", " ")[0, 380],
      fields: [
        field("Category", @idea_capture.category),
        field("Department", @idea_capture.department),
        field("Proposed solution", @idea_capture.proposed_solution),
        field("Impact hypothesis", @idea_capture.impact),
        field("Next step", @idea_capture.next_step),
        field("Conversation", admin_url)
      ],
      footer: {
        text: "Athena rev cycle ideation"
      }
    }
  end

  def openclaw_message
    <<~TEXT
      Athena captured a rev cycle idea:

      Title: #{@idea_capture.title}
      Category: #{@idea_capture.category}
      Problem: #{@idea_capture.problem}
      Proposed solution: #{@idea_capture.proposed_solution}
      Impact: #{@idea_capture.impact}
      Next step: #{@idea_capture.next_step}
      Conversation: #{admin_url || "No admin URL configured"}
    TEXT
  end

  def field(name, value)
    {
      name: name,
      value: value.to_s.tr("\n", " ")[0, 1024].presence || "-",
      inline: false
    }
  end

  def webhook_url
    AppSetting.fetch("ATHENA_IDEAS_DISCORD_WEBHOOK_URL").to_s.strip.presence
  end

  def discord_username
    AppSetting.fetch("ATHENA_IDEAS_DISCORD_USERNAME").to_s.strip.presence ||
      "Athena"
  end

  def discord_channel
    AppSetting.fetch("ATHENA_IDEAS_DISCORD_CHANNEL").to_s.strip.presence || "discord"
  end

  def discord_target
    AppSetting.fetch("ATHENA_IDEAS_DISCORD_TARGET").to_s.strip.presence
  end

  def openclaw_cli
    value = AppSetting.fetch("OPENCLAW_CLI").to_s.strip
    value.present? && value != "1" ? value : "openclaw"
  end

  def openclaw_profile
    AppSetting.fetch("ATHENA_IDEAS_OPENCLAW_PROFILE").to_s.strip.presence ||
      AppSetting.fetch("OPENCLAW_PROFILE").to_s.strip.presence ||
      "default"
  end

  def admin_url
    base_url = AppSetting.fetch("PUBLIC_BASE_URL").to_s.strip
    return if base_url.blank?

    "#{base_url}/admin/idea_captures/#{@idea_capture.id}"
  end

  def message_id_from(output)
    parsed = parse_json(output)
    parsed.dig("payload", "id") ||
      parsed.dig("payload", "message", "id") ||
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
    stdout, stderr, status = Open3.capture3("timeout", "30", *args)
    CommandResult.new(stdout: stdout, stderr: stderr, exitstatus: status.exitstatus)
  end

  def command_error(result)
    detail = result.stderr.to_s.strip.presence || result.stdout.to_s.strip.presence || "exit #{result.exitstatus}"
    { ok: false, provider: "openclaw", channel: discord_channel, target: discord_target, error: "Athena idea Discord report failed: #{detail}" }
  end
end
