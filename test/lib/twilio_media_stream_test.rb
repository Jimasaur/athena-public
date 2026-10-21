require "test_helper"
require "base64"

class TwilioMediaStreamTest < ActiveSupport::TestCase
  class FakeWebSocket
    attr_reader :close_args

    def close(*args)
      @close_args = args
    end
  end

  class FakeBridge
    attr_reader :received_media, :closed

    def initialize
      @received_media = []
      @closed = false
    end

    def receive_twilio_media(payload)
      @received_media << payload
    end

    def close
      @closed = true
    end
  end

  setup do
    conversations(:one).update!(twilio_call_sid: call_events(:one).twilio_call_sid)
    conversations(:two).update!(twilio_call_sid: call_events(:two).twilio_call_sid)
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
    ws = FakeWebSocket.new
    stream.send(:handle_start, {
      "event" => "start",
      "start" => {
        "callSid" => call_sid,
        "streamSid" => "MZ-recording-test",
        "customParameters" => {
          "provider" => "twilio",
          "stream_token" => stream_token
        }
      }
    }, ws)
    stream.send(:handle_media, {
      "event" => "media",
      "streamSid" => "MZ-recording-test",
      "media" => {
        "track" => "inbound",
        "timestamp" => "0",
        "payload" => Base64.strict_encode64(("\xff".b * 160))
      }
    }, ws)
    stream.send(:handle_stop, {
      "event" => "stop",
      "streamSid" => "MZ-recording-test",
      "stop" => {
        "callSid" => call_sid
      }
    }, ws)

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

  test "media and stop require an authenticated start even when call ids are known" do
    conversation = conversations(:one)
    stream = TwilioMediaStream.new
    ws = FakeWebSocket.new
    broadcasts = []

    assert_no_difference "CallEvent.count" do
      with_audio_broadcasts(broadcasts) do
        stream.send(:handle_message, media_payload(conversation.twilio_call_sid).to_json, ws)
        stream.send(:handle_message, stop_payload(conversation.twilio_call_sid).to_json, ws)
      end
    end

    assert_empty broadcasts
    assert_empty stream.send(:stream_recordings)
    assert_not conversation.reload.recording.attached?
  end

  test "another socket cannot inject audio or stop an authenticated stream" do
    conversation = conversations(:one)
    stream = TwilioMediaStream.new
    owner = FakeWebSocket.new
    intruder = FakeWebSocket.new
    start_stream(stream, conversation, owner)
    bridge = FakeBridge.new
    stream.send(:realtime_bridges)["MZ-authorized"] = bridge
    broadcasts = []

    assert_no_difference "CallEvent.count" do
      with_audio_broadcasts(broadcasts) do
        stream.send(:handle_message, media_payload(conversation.twilio_call_sid).to_json, intruder)
        stream.send(:handle_message, stop_payload(conversation.twilio_call_sid).to_json, intruder)
      end
    end

    assert_empty broadcasts
    assert_empty bridge.received_media
    assert_not bridge.closed
    assert_empty stream.send(:stream_recordings)["MZ-authorized"]

    # Twilio media normally omits callSid; the verified start supplies it.
    payload = media_payload
    with_audio_broadcasts(broadcasts) do
      stream.send(:handle_message, payload.to_json, owner)
    end
    assert_equal [ payload ], bridge.received_media
    assert_equal 1, broadcasts.size
    assert_equal 1, stream.send(:stream_recordings)["MZ-authorized"].size

    stream.send(:handle_message, stop_payload(conversation.twilio_call_sid).to_json, owner)

    assert bridge.closed
    assert conversation.reload.recording.attached?
    assert conversation.call_events.where(status: "twilio_stream_stopped").exists?
    assert_empty stream.send(:stream_map)
    assert_empty stream.send(:stream_recordings)
  end

  test "authenticated stream cannot override its call id" do
    conversation = conversations(:one)
    stream = TwilioMediaStream.new
    ws = FakeWebSocket.new
    start_stream(stream, conversation, ws)
    broadcasts = []

    assert_no_difference "CallEvent.count" do
      with_audio_broadcasts(broadcasts) do
        stream.send(:handle_message, media_payload(conversations(:two).twilio_call_sid).to_json, ws)
        stream.send(:handle_message, stop_payload(conversations(:two).twilio_call_sid).to_json, ws)
      end
    end

    assert_empty broadcasts
    assert_empty stream.send(:stream_recordings)["MZ-authorized"]
    assert stream.send(:stream_map).key?("MZ-authorized")
  end

  test "duplicate starts cannot replace stream ownership or erase recordings" do
    conversation = conversations(:one)
    stream = TwilioMediaStream.new
    owner = FakeWebSocket.new
    intruder = FakeWebSocket.new
    start_stream(stream, conversation, owner)
    with_audio_broadcasts do
      stream.send(:handle_message, media_payload.to_json, owner)
    end

    assert_no_difference "CallEvent.count" do
      start_stream(stream, conversation, owner)
      start_stream(stream, conversation, intruder)
    end

    assert_equal [ 1008, "Invalid stream token" ], intruder.close_args
    assert_same owner, stream.send(:stream_map)["MZ-authorized"][:socket]
    assert_equal 1, stream.send(:stream_recordings)["MZ-authorized"].size
  end

  test "socket close releases only its authenticated stream state" do
    conversation = conversations(:one)
    stream = TwilioMediaStream.new
    owner = FakeWebSocket.new
    start_stream(stream, conversation, owner)
    bridge = FakeBridge.new
    stream.send(:realtime_bridges)["MZ-authorized"] = bridge

    stream.send(:close_bridges_for_socket, FakeWebSocket.new)
    assert_not bridge.closed
    assert stream.send(:stream_map).key?("MZ-authorized")

    stream.send(:close_bridges_for_socket, owner)

    assert bridge.closed
    assert_empty stream.send(:stream_map)
    assert_empty stream.send(:stream_recordings)
    assert_empty stream.send(:realtime_bridges)
  end

  private

  def with_audio_broadcasts(broadcasts = [])
    original = CallAudioChannel.method(:broadcast_to)
    CallAudioChannel.define_singleton_method(:broadcast_to) { |*args| broadcasts << args }
    yield
  ensure
    CallAudioChannel.define_singleton_method(:broadcast_to, original)
  end

  def start_stream(stream, conversation, ws)
    conversation.call_state.update!(state: conversation.call_state.state.merge("twilio_stream_token" => "owner-token"))
    stream.send(:handle_message, {
      "event" => "start",
      "start" => {
        "callSid" => conversation.twilio_call_sid,
        "streamSid" => "MZ-authorized",
        "customParameters" => { "provider" => "twilio", "stream_token" => "owner-token" }
      }
    }.to_json, ws)
  end

  def media_payload(call_sid = nil)
    {
      "event" => "media",
      "streamSid" => "MZ-authorized",
      "media" => {
        "track" => "inbound",
        "timestamp" => "0",
        "payload" => Base64.strict_encode64("\xff".b * 160)
      }.tap { |media| media["callSid"] = call_sid if call_sid }
    }
  end

  def stop_payload(call_sid)
    { "event" => "stop", "streamSid" => "MZ-authorized", "stop" => { "callSid" => call_sid } }
  end
end
