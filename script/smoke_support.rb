# frozen_string_literal: true

require "json"
require "securerandom"
require_relative "../config/environment"

class SmokeReport
  attr_reader :checks

  def initialize(title)
    @title = title
    @checks = []
  end

  def check(name)
    yield
    @checks << { name: name, ok: true }
  rescue StandardError => error
    @checks << {
      name: name,
      ok: false,
      error: "#{error.class}: #{error.message}"
    }
  end

  def skip(name, reason)
    @checks << { name: name, ok: true, skipped: true, reason: reason }
  end

  def assert(condition, message)
    raise RuntimeError, message unless condition
  end

  def finish!(extra = {})
    ok = @checks.all? { |check| check[:ok] }
    puts JSON.pretty_generate(
      {
        ok: ok,
        title: @title,
        checks: @checks
      }.merge(extra)
    )
    exit(ok ? 0 : 1)
  end
end

module SmokeSupport
  module_function

  def session
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! ENV.fetch("SMOKE_HOST", "localhost")
    end
  end

  def json_body(session)
    JSON.parse(session.response.body)
  rescue JSON::ParserError
    {}
  end

  def tool_headers
    secret = AppSetting.fetch("ATHENA_TOOL_SECRET").to_s
    return {} if secret.blank?

    { "X-Athena-Tool-Secret" => secret }
  end

  def smoke_customer(phone_number: ENV.fetch("CALLER_PHONE", "+14155550177"))
    Customer.find_or_create_by!(phone_number: phone_number) do |customer|
      customer.name = "Smoke Test Caller"
      customer.greeting_name = "Smoke"
      customer.metadata = { "source" => "smoke" }
    end
  end

  def smoke_agent
    AgentSetting.where.not(twilio_number: [ nil, "" ]).order(:id).first ||
      AgentSetting.find_or_create_by!(agent_id: "smoke-agent") do |agent|
        agent.name = "Smoke Agent"
        agent.system_prompt = "You are a smoke-test voice agent."
        agent.first_message = "Hello from Athena."
        agent.voice_id = "smoke-voice"
        agent.tool_url = "https://example.test/agent_tools/command"
        agent.twilio_number = "+14155551234"
        agent.tools = []
        agent.data = { "source" => "smoke" }
      end
  end

  def allowed_smoke_caller
    return ENV["CALLER_PHONE"] if ENV["CALLER_PHONE"].present?

    raw = AppSetting.fetch("TWILIO_ALLOWED_CALLERS").to_s.split(/[,\s]+/).first
    digits = raw.to_s.gsub(/\D/, "")
    return "+14155550177" if digits.blank?

    digits = digits.sub(/^1(?=\d{10}$)/, "")
    "+1#{digits}"
  end
end
