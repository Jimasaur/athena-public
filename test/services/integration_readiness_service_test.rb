require "test_helper"
require "resolv"

class IntegrationReadinessServiceTest < ActiveSupport::TestCase
  Agent = Struct.new(:twilio_number)

  test "local synthetic demo is separate from missing live configuration" do
    report = readiness

    assert_equal :configured, report[:local_demo][:status]
    assert_includes report[:local_demo][:detail], "simulated"
    assert_equal :missing, row(report, "OpenAI Realtime")[:status]
    assert_equal :missing, row(report, "Twilio voice credentials")[:status]
    assert_equal :missing, row(report, "Realtime agent profile")[:status]
    assert_equal :missing, row(report, "Twilio number mapping")[:status]
    assert_equal :missing, row(report, "Public webhook URL")[:status]
  end

  test "placeholder values require review instead of appearing configured" do
    report = readiness({
      "OPENAI_API_KEY" => "YOUR_OPENAI_API_KEY",
      "TWILIO_ACCOUNT_SID" => "AC123",
      "TWILIO_AUTH_TOKEN" => "change-this",
      "PUBLIC_BASE_URL" => "https://example.com",
      "ATHENA_IDEAS_DISCORD_TARGET" => "channel:YOUR_CHANNEL_ID",
      "ATHENA_TOOL_SECRET" => "replace_me"
    })

    [ "OpenAI Realtime", "Twilio voice credentials", "Public webhook URL", "Athena idea Discord", "Tool authentication" ].each do |label|
      assert_equal :needs_review, row(report, label)[:status], label
    end
  end

  test "OpenAI uses the application default model when no override is supplied" do
    report = readiness({ "OPENAI_API_KEY" => "test-private-key-value" })

    assert_equal :configured, row(report, "OpenAI Realtime")[:status]
    assert_includes row(report, "OpenAI Realtime")[:detail], "have not been tested"
    assert_equal :needs_review, row(readiness({ "OPENAI_API_KEY" => "sk-value", "OPENAI_REALTIME_MODEL" => "YOUR_MODEL" }), "OpenAI Realtime")[:status]
  end

  test "database override is authoritative even when an environment key is present" do
    original = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "test-environment-key-value"
    AppSetting.find_or_initialize_by(key: "OPENAI_API_KEY").update!(value: "")

    report = IntegrationReadinessService.new(agents: [], environment: "development").call

    assert_equal :missing, row(report, "OpenAI Realtime")[:status]
  ensure
    ENV["OPENAI_API_KEY"] = original
  end

  test "public webhook configuration rejects local malformed and credential-bearing URLs" do
    invalid_urls = [
      "http://voice.acme.tools", "https://localhost", "https://127.0.0.1", "https://[::1]",
      "https://192.168.1.8", "https://169.254.169.254", "https://224.0.0.1", "https://voice.acme.test",
      "https://voice.acme.tools/voice/inbound", "https://user:password@voice.acme.tools",
      "https://voice.acme.tools?token=hidden", "https://voice.acme.tools#fragment", "invalid URL"
    ]

    invalid_urls.each do |url|
      assert_equal :needs_review, row(readiness({ "PUBLIC_BASE_URL" => url }), "Public webhook URL")[:status], url
    end

    [ "https://voice.acme.tools", "https://voice.acme.tools/" ].each do |url|
      assert_equal :configured, row(readiness({ "PUBLIC_BASE_URL" => url }), "Public webhook URL")[:status], url
    end
  end

  test "configuration report never returns secrets or private webhook tokens" do
    secrets = {
      "TWILIO_ACCOUNT_SID" => "AC-private-account-id",
      "TWILIO_AUTH_TOKEN" => "private-twilio-token",
      "OPENAI_API_KEY" => "sk-private-openai-key",
      "ATHENA_TOOL_SECRET" => "private-tool-secret",
      "ADMIN_USERNAME" => "private-admin-name",
      "ADMIN_PASSWORD" => "private-admin-password",
      "ATHENA_IDEAS_DISCORD_WEBHOOK_URL" => "https://discord.com/api/webhooks/123/private-webhook-token"
    }
    serialized_report = readiness(secrets).to_json

    secrets.each_value { |secret| assert_not_includes serialized_report, secret }
    assert_not_includes serialized_report, "private-webhook-token"
  end

  test "public URL and webhook inventory never resolves hosts or probes providers" do
    original_resolver = Resolv.method(:getaddresses)
    Resolv.define_singleton_method(:getaddresses) { |_host| raise "Readiness must not resolve hosts" }

    report = readiness({
      "PUBLIC_BASE_URL" => "https://voice.acme.tools",
      "ATHENA_IDEAS_DISCORD_WEBHOOK_URL" => "https://discord.com/api/webhooks/123/secret"
    })

    assert_equal :configured, row(report, "Public webhook URL")[:status]
    assert_equal :configured, row(report, "Athena idea Discord")[:status]
  ensure
    Resolv.define_singleton_method(:getaddresses) { |host| original_resolver.call(host) }
  end

  test "Discord reports respect webhook precedence and reject a placeholder webhook" do
    report = readiness({
      "ATHENA_IDEAS_DISCORD_WEBHOOK_URL" => "https://YOUR_WEBHOOK_URL",
      "ATHENA_IDEAS_DISCORD_TARGET" => "channel:123456789"
    })
    assert_equal :needs_review, row(report, "Athena idea Discord")[:status]

    valid_report = readiness({ "ATHENA_IDEAS_DISCORD_WEBHOOK_URL" => "https://discord.com/api/webhooks/123/secret" })
    assert_equal :configured, row(valid_report, "Athena idea Discord")[:status]

    invalid_report = readiness({ "ATHENA_IDEAS_DISCORD_WEBHOOK_URL" => "https://voice.acme.tools/hook" })
    assert_equal :needs_review, row(invalid_report, "Athena idea Discord")[:status]
  end

  test "sample and malformed phone mappings require review" do
    [ "+15551234567", "+14155551234", "YOUR_NUMBER", "6125559999" ].each do |number|
      assert_equal :needs_review, row(readiness({}, agents: [ Agent.new(number) ]), "Twilio number mapping")[:status], number
    end

    report = readiness({}, agents: [ Agent.new("+16125559876") ])
    assert_equal :configured, row(report, "Realtime agent profile")[:status]
    assert_equal :configured, row(report, "Twilio number mapping")[:status]
    assert_includes row(report, "Twilio number mapping")[:detail], "have not been tested"
  end

  test "explicit access settings and production call scope are reported without probing" do
    settings = {
      "ADMIN_USERNAME" => "operator",
      "ADMIN_PASSWORD" => "a-private-password",
      "ATHENA_TOOL_SECRET" => "a-private-tool-secret",
      "TWILIO_VERIFY_WEBHOOK_SIGNATURES" => "true"
    }
    report = readiness(settings, environment: "production")

    assert report[:security].all? { |item| item[:status] == :configured }
    assert_equal :needs_review, row(readiness, "Call-scoped tools")[:status]
    assert_equal :needs_review, row(readiness({ "TWILIO_VERIFY_WEBHOOK_SIGNATURES" => "false" }), "Twilio signatures")[:status]
    assert_equal :configured, row(readiness({ "ATHENA_AGENT_TOOLS_REQUIRE_CONTEXT" => "true" }), "Call-scoped tools")[:status]
    assert_equal :configured, row(readiness({ "PUBLIC_BASE_URL" => "https://voice.acme.tools" }), "Call-scoped tools")[:status]
  end

  test "proxy admin authentication needs both demo mode and a real shared secret" do
    settings = { "ATHENA_PROXY_AUTH_SECRET" => "a-private-proxy-secret" }
    assert_equal :missing, row(readiness(settings), "Admin authentication")[:status]

    settings["ATHENA_PUBLIC_DEMO_MODE"] = "true"
    assert_equal :configured, row(readiness(settings), "Admin authentication")[:status]

    settings["ATHENA_PROXY_AUTH_SECRET"] = "change-this"
    assert_equal :needs_review, row(readiness(settings), "Admin authentication")[:status]
  end

  test "optional local route settings do not imply an installed or running sidecar" do
    report = readiness({ "OPENCLAW_PROFILE" => "default", "OPENCLAW_AGENT" => "main" })

    assert_equal :configured, row(report, "Local AI sidecar route")[:status]
    assert_includes row(report, "Local AI sidecar route")[:detail], "have not been tested"
  end

  private

  def readiness(settings = {}, agents: [], environment: "development")
    IntegrationReadinessService.new(settings: settings, agents: agents, environment: environment).call
  end

  def row(report, label)
    (report[:integrations] + report[:security]).find { |item| item[:label] == label } || flunk("Missing readiness row: #{label}")
  end
end
