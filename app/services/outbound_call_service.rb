class OutboundCallService
  Result = Struct.new(:call_sid, :error, keyword_init: true)

  def initialize(base_url:)
    @base_url = base_url
  end

  def call(agent_setting:, to_number:)
    account_sid = AppSetting.fetch("TWILIO_ACCOUNT_SID")
    auth_token = AppSetting.fetch("TWILIO_AUTH_TOKEN")
    return Result.new(error: "Missing TWILIO_ACCOUNT_SID or TWILIO_AUTH_TOKEN.") if account_sid.blank? || auth_token.blank?

    from_number = agent_setting.twilio_number.to_s.strip
    to_number = to_number.to_s.strip
    return Result.new(error: "Agent is missing a Twilio number.") if from_number.blank?
    return Result.new(error: "Missing destination phone number.") if to_number.blank?

    helpers = Rails.application.routes.url_helpers
    outbound_url = URI.join(@base_url, helpers.twilio_outbound_path)
    outbound_url.query = URI.encode_www_form(agent_id: agent_setting.agent_id)
    status_url = URI.join(@base_url, helpers.twilio_status_webhook_path).to_s

    client = Twilio::REST::Client.new(account_sid, auth_token)
    call = client.calls.create(
      from: from_number,
      to: to_number,
      url: outbound_url.to_s,
      method: "POST",
      status_callback: status_url,
      status_callback_method: "POST"
    )

    Result.new(call_sid: call.sid)
  rescue StandardError => error
    Result.new(error: error.message)
  end
end
