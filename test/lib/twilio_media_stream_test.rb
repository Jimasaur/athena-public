require "test_helper"
require "base64"

class TwilioMediaStreamTest < ActiveSupport::TestCase
  class FakeWebSocket
    attr_reader :close_args

    def close(*args)
      @close_args = args
    end
  end

  test "attaches a wav recording from media frames when stream stops" do
    conversation = conversations(:one)
    call_sid = "CA-recording-test"
    stream_token = "valid-stream-token"
    conversation.call_state.update!(state: conversation.call_state.state.merge("twilio_stream_token" => stream_token))
    conversation.call_events.create!(
      twilio_call_sid: call_sid,
      status: "in_progress",
      direction: "inbound"
    )

    stream = TwilioMediaStream.new
    stream.send(:handle_start, {
      "event" => "start",
      "start" => {
        "callSid" => call_sid,
        "streamSid" => "MZ-recording-test",
        "customParameters" => {
          "stream_token" => stream_token
        }
      }
    })
    stream.send(:handle_media, {
      "event" => "media",
      "streamSid" => "MZ-recording-test",
      "media" => {
        "track" => "inbound",
        "timestamp" => "0",
        "payload" => Base64.strict_encode64(("\xff".b * 160))
      }
    })
    stream.send(:handle_stop, {
      "event" => "stop",
      "streamSid" => "MZ-recording-test",
      "stop" => {
        "callSid" => call_sid
      }
    })

    assert conversation.reload.recording.attached?
    assert_includes [ "audio/wav", "audio/x-wav" ], conversation.recording.blob.content_type
    assert conversation.recording.download.start_with?("RIFF")
    assert conversation.call_events.where(status: "twilio_stream_recording").exists?
    assert_nil conversation.call_events.where(status: "twilio_stream_started").last.data.dig("start", "customParameters", "stream_token")
  end

  test "rejects media stream start without the per-call token" do
    conversation = conversations(:one)
    call_sid = "CA-rejected-stream-test"
    conversation.call_state.update!(state: conversation.call_state.state.merge("twilio_stream_token" => "expected-token"))
    conversation.call_events.create!(
      twilio_call_sid: call_sid,
      status: "in_progress",
      direction: "inbound"
    )

    ws = FakeWebSocket.new
    stream = TwilioMediaStream.new

    assert_difference -> { conversation.call_events.where(status: "twilio_stream_rejected").count }, 1 do
      stream.send(:handle_start, {
        "event" => "start",
        "start" => {
          "callSid" => call_sid,
          "streamSid" => "MZ-rejected-stream-test",
          "customParameters" => {
            "stream_token" => "wrong-token"
          }
        }
      }, ws)
    end

    assert_equal [ 1008, "Invalid stream token" ], ws.close_args
    assert_nil conversation.call_events.where(status: "twilio_stream_rejected").last.data.dig("start", "customParameters", "stream_token")
  end
end
