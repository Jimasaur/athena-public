require "test_helper"

class TwilioSignatureVerificationTest < ActionDispatch::IntegrationTest
  test "rejects unsigned Twilio webhook when verification is enabled" do
    AppSetting.create!(key: "TWILIO_VERIFY_WEBHOOK_SIGNATURES", value: "true")

    post "/voice/outbound/status", params: {
      "CallSid" => call_events(:one).twilio_call_sid,
      "CallStatus" => "completed"
    }

    assert_response :unauthorized
  end

  test "accepts signed Twilio webhook when verification is enabled" do
    AppSetting.create!(key: "TWILIO_VERIFY_WEBHOOK_SIGNATURES", value: "true")

    payload = {
      "CallSid" => call_events(:one).twilio_call_sid,
      "CallStatus" => "completed",
      "Direction" => "outbound-api",
      "From" => agent_settings(:one).twilio_number,
      "To" => customers(:one).phone_number
    }
    url = "#{app_settings(:public_base_url).value}/voice/outbound/status"
    signature = Twilio::Security::RequestValidator
      .new(app_settings(:twilio_auth_token).value)
      .build_signature_for(url, payload)

    post "/voice/outbound/status", params: payload, headers: { "X-Twilio-Signature" => signature }

    assert_response :ok
  end
end
