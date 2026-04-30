require "test_helper"

class TwilioVoicebotCompatibilityTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "voice inbound alias returns OpenAI Realtime TwiML by default" do
    Customer.find_or_create_by!(phone_number: "+14155552001") do |customer|
      customer.name = "Jordan"
    end.update!(metadata: { "email" => "operator@example.com" })

    post "/voice/inbound", params: {
      "CallSid" => "CA123",
      "From" => "+14155552001",
      "To" => agent_settings(:one).twilio_number
    }

    assert_response :ok
    assert_includes response.body, "wss://config.example.test/ws/twilio-media"
    assert_not_includes response.body, "https://config.example.test/webhooks/twilio/transcription"
    assert_not_includes response.body, "inboundTrackLabel=\"user\""
    assert_not_includes response.body, "outboundTrackLabel=\"agent\""
    assert_includes response.body, "name=\"provider\" value=\"openai_realtime\""
    assert_includes response.body, "name=\"stream_token\""

    conversation = Conversation.find_by!(twilio_call_sid: "CA123")
    assert_equal "openai_realtime", conversation.call_state.provider
    assert_equal "rev-cycle-ideation-session", conversation.call_state.use_case_slug
    assert conversation.call_state.state["twilio_stream_token"].present?
  end

  test "voice inbound ignores provider overrides" do
    Customer.find_or_create_by!(phone_number: "+14155552001") do |customer|
      customer.name = "Jordan"
    end

    post "/voice/inbound", params: {
      "CallSid" => "CA-openai-realtime",
      "From" => "+14155552001",
      "To" => agent_settings(:one).twilio_number,
      "VoiceProvider" => "legacy"
    }

    assert_response :ok
    assert_includes response.body, "<Connect>"
    assert_includes response.body, "wss://config.example.test/ws/twilio-media"
    assert_includes response.body, "name=\"provider\" value=\"openai_realtime\""
    assert_includes response.body, "name=\"call_sid\" value=\"CA-openai-realtime\""
    assert_includes response.body, "name=\"stream_token\""
    assert_not_includes response.body, "https://config.example.test/webhooks/twilio/transcription"

    conversation = Conversation.find_by!(twilio_call_sid: "CA-openai-realtime")
    assert_equal "openai_realtime", conversation.call_state.provider
    assert_equal "rev-cycle-ideation-session", conversation.call_state.use_case_slug
    assert_equal "openai_realtime", conversation.call_events.order(:created_at).first.data["provider"]
  end

  test "voice inbound can enable Twilio transcript mirror for diagnostics" do
    AppSetting.create!(key: "OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED", value: "true")

    post "/voice/inbound", params: {
      "CallSid" => "CA-transcript-mirror",
      "From" => "+14155552001",
      "To" => agent_settings(:one).twilio_number
    }

    assert_response :ok
    assert_includes response.body, "https://config.example.test/webhooks/twilio/transcription"
    assert_includes response.body, "inboundTrackLabel=\"user\""
    assert_includes response.body, "outboundTrackLabel=\"agent\""
  end

  test "transcription webhook maps outbound track to assistant" do
    call_sid = call_events(:one).twilio_call_sid

    post "/webhooks/twilio/transcription", params: {
      "CallSid" => call_sid,
      "Track" => "outbound_track",
      "TranscriptionText" => "Hello from the voice agent.",
      "Timestamp" => Time.current.iso8601
    }

    assert_response :ok
    message = conversations(:one).messages.find_by!(content: "Hello from the voice agent.")
    assert_equal "assistant", message.role
  end

  test "voice outbound status alias records call event" do
    conversation = conversations(:one)
    call_sid = call_events(:one).twilio_call_sid

    post "/voice/outbound/status", params: {
      "CallSid" => call_sid,
      "CallStatus" => "completed",
      "Direction" => "outbound-api",
      "From" => "+14155551234",
      "To" => customers(:one).phone_number
    }

    assert_response :ok
    assert_equal "completed", conversation.call_events.order(:created_at).last.status
    assert_equal "completed", conversation.reload.status
  end

  test "completed Twilio call creates fallback email approval from transcript" do
    conversation = conversations(:one)
    conversation.update!(twilio_call_sid: "CA-fallback-email")
    conversation.sidecar_events.destroy_all
    conversation.messages.destroy_all
    conversation.customer.update!(metadata: conversation.customer.metadata.merge("email" => "operator@example.com"))
    conversation.messages.create!(role: "assistant", content: "Here is the draft subject Demo follow up", sent_at: 3.minutes.ago)
    conversation.messages.create!(role: "assistant", content: "Jordan, this is the demo follow up body.", sent_at: 2.minutes.ago)
    conversation.messages.create!(role: "user", content: "Email me this and send me approval.", sent_at: 1.minute.ago)

    assert_enqueued_with(job: AthenaTranscriptEmailJob) do
      assert_enqueued_with(job: GemmaMailApprovalJob) do
        assert_difference "conversation.sidecar_events.where(kind: 'email_approval.queued').count", 1 do
          post "/voice/outbound/status", params: {
            "CallSid" => "CA-fallback-email",
            "CallStatus" => "completed",
            "Direction" => "inbound",
            "From" => "+14155552001",
            "To" => agent_settings(:one).twilio_number
          }
        end
      end
    end

    assert_response :ok
  end
end
