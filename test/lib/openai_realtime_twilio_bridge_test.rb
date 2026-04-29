require "test_helper"

class OpenaiRealtimeTwilioBridgeTest < ActiveSupport::TestCase
  class FakeTwilioWebSocket
    attr_reader :sent

    def initialize
      @sent = []
    end

    def send(payload)
      @sent << JSON.parse(payload)
    end

    def close; end
  end

  test "session update configures OpenAI Realtime for Twilio audio and Athena tools" do
    bridge = build_bridge
    event = bridge.send(:session_update_event)

    assert_equal "session.update", event[:type]
    session = event[:session]
    assert_equal "realtime", session[:type]
    assert_equal [ "audio" ], session[:output_modalities]
    assert_equal "audio/pcmu", session.dig(:audio, :input, :format, :type)
    assert_equal "audio/pcmu", session.dig(:audio, :output, :format, :type)
    assert_equal "near_field", session.dig(:audio, :input, :noise_reduction, :type)
    assert_equal "gpt-4o-mini-transcribe", session.dig(:audio, :input, :transcription, :model)
    assert_equal "server_vad", session.dig(:audio, :input, :turn_detection, :type)
    assert_equal 0.65, session.dig(:audio, :input, :turn_detection, :threshold)
    assert_equal 500, session.dig(:audio, :input, :turn_detection, :silence_duration_ms)
    assert_equal false, session.dig(:audio, :input, :turn_detection, :interrupt_response)
    assert_equal "athena_command", session.dig(:tools, 0, :name)
    assert_includes session[:instructions], "approval workflow"
    assert_includes session[:instructions], "Brave Search snippets"
    assert_includes session[:instructions], "Do you want to add another idea"
    assert_includes session[:instructions], "Do not repeat or restate the greeting"
    assert_includes session[:instructions], "calm, measured pace"
  end

  test "forwards OpenAI audio deltas to Twilio media stream" do
    twilio_ws = FakeTwilioWebSocket.new
    bridge = build_bridge(twilio_ws: twilio_ws)

    bridge.send(:forward_openai_audio, "base64-audio")

    assert_equal "media", twilio_ws.sent.last["event"]
    assert_equal "MZ-test", twilio_ws.sent.last["streamSid"]
    assert_equal "base64-audio", twilio_ws.sent.last.dig("media", "payload")
  end

  test "stores realtime transcripts as conversation messages" do
    conversation = conversations(:one)
    bridge = build_bridge(conversation: conversation)

    assert_difference "conversation.messages.where(role: 'user').count", 1 do
      bridge.send(:create_transcript_message, "user", "Please search the web.")
    end

    assert_equal "Please search the web.", conversation.messages.order(:created_at).last.content
  end

  test "logged tool results keep audit-friendly reply details" do
    bridge = build_bridge
    result = bridge.send(
      :logged_tool_result,
      {
        "ok" => true,
        "command" => "semantic_request",
        "intent" => "weather",
        "provider" => "brave_search",
        "reply" => "I searched Brave Search for current weather.",
        "results" => [ { "title" => "Weather" } ]
      }
    )

    assert_equal true, result[:ok]
    assert_equal "weather", result[:intent]
    assert_equal "I searched Brave Search for current weather.", result[:reply]
    assert_equal 1, result[:results_count]
  end

  test "session update can use semantic vad and advanced overrides" do
    AppSetting.create!(key: "OPENAI_REALTIME_TURN_DETECTION_TYPE", value: "semantic_vad")
    AppSetting.create!(key: "OPENAI_REALTIME_SEMANTIC_EAGERNESS", value: "low")
    AppSetting.create!(key: "OPENAI_REALTIME_SESSION_OVERRIDES_JSON", value: { audio: { output: { voice: "cedar" } } }.to_json)

    session = build_bridge.send(:session_update_event)[:session]

    assert_equal "semantic_vad", session.dig(:audio, :input, :turn_detection, :type)
    assert_equal "low", session.dig(:audio, :input, :turn_detection, :eagerness)
    assert_equal "cedar", session.dig(:audio, :output, :voice)
  end

  test "speech started does not clear opening audio during grace period" do
    twilio_ws = FakeTwilioWebSocket.new
    bridge = build_bridge(twilio_ws: twilio_ws)
    bridge.instance_variable_set(:@connected_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))

    assert_difference "conversations(:one).call_events.where(status: 'openai_realtime_speech_started').count", 1 do
      bridge.send(:handle_speech_started, { "audio_start_ms" => 100 })
    end

    assert_empty twilio_ws.sent.select { |payload| payload["event"] == "clear" }
  end

  private

  def build_bridge(twilio_ws: FakeTwilioWebSocket.new, conversation: conversations(:one))
    OpenaiRealtimeTwilioBridge.new(
      twilio_ws: twilio_ws,
      conversation: conversation,
      call_sid: "CA-test",
      stream_sid: "MZ-test",
      agent_setting: agent_settings(:one),
      custom_parameters: {}
    )
  end
end
