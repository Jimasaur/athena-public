require "test_helper"
require "base64"

class TwilioMediaStreamTest < ActiveSupport::TestCase
  test "attaches a wav recording from media frames when stream stops" do
    conversation = conversations(:one)
    call_sid = "CA-recording-test"
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
        "streamSid" => "MZ-recording-test"
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
  end
end
