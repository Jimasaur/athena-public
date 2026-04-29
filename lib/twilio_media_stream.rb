require "faye/websocket"
require "base64"
require "json"
require "stringio"

class TwilioMediaStream
  KEEPALIVE_TIME = 15
  SAMPLE_RATE = 8_000
  MAX_FRAMES_PER_STREAM = 120_000

  def call(env)
    unless Faye::WebSocket.websocket?(env)
      return [ 426, { "Content-Type" => "text/plain" }, [ "Expected WebSocket connection." ] ]
    end

    ws = Faye::WebSocket.new(env, nil, ping: KEEPALIVE_TIME)
    ws.on :message do |event|
      handle_message(event.data, ws)
    end
    ws.on :close do |_event|
      close_bridges_for_socket(ws)
    end

    ws.rack_response
  end

  private

  def stream_map
    @stream_map ||= {}
  end

  def stream_recordings
    @stream_recordings ||= {}
  end

  def realtime_bridges
    @realtime_bridges ||= {}
  end

  def handle_message(raw, ws = nil)
    payload = JSON.parse(raw)
    case payload["event"]
    when "start"
      handle_start(payload, ws)
    when "media"
      handle_media(payload)
    when "stop"
      handle_stop(payload)
    end
  rescue JSON::ParserError
    nil
  end

  def handle_start(payload, ws = nil)
    call_sid = payload.dig("start", "callSid")
    stream_sid = payload.dig("start", "streamSid") || payload["streamSid"]
    return if call_sid.blank?

    conversation = conversation_for_call(call_sid)
    return if conversation.blank?

    unless valid_stream_token?(conversation, payload)
      record_rejected_start(conversation, call_sid, payload)
      close_socket(ws)
      return
    end

    stream_map[stream_sid] = call_sid if stream_sid.present?
    stream_recordings[stream_sid] = [] if stream_sid.present?

    conversation.call_events.create!(
      twilio_call_sid: call_sid,
      status: "twilio_stream_started",
      direction: "inbound",
      data: sanitized_stream_payload(payload)
    )

    start_openai_realtime_bridge(ws, conversation, call_sid, stream_sid, payload) if openai_realtime_stream?(conversation, payload)
  end

  def handle_stop(payload)
    call_sid = payload.dig("stop", "callSid")
    stream_sid = payload.dig("stop", "streamSid") || payload["streamSid"]
    return if call_sid.blank?

    stream_map.delete(stream_sid) if stream_sid.present?
    frames = stream_sid.present? ? stream_recordings.delete(stream_sid) : nil
    close_realtime_bridge(stream_sid) if stream_sid.present?

    conversation = conversation_for_call(call_sid)
    return if conversation.blank?

    attach_recording(conversation, call_sid, frames) if frames.present?

    conversation.call_events.create!(
      twilio_call_sid: call_sid,
      status: "twilio_stream_stopped",
      direction: "inbound",
      data: payload
    )
  end

  def handle_media(payload)
    stream_sid = payload["streamSid"]
    call_sid = payload.dig("media", "callSid") || stream_map[stream_sid]
    return if call_sid.blank?

    conversation = conversation_for_call(call_sid)
    return if conversation.blank?

    record_media_frame(stream_sid, payload)
    realtime_bridges[stream_sid]&.receive_twilio_media(payload)

    CallAudioChannel.broadcast_to(
      conversation,
      type: "media",
      track: payload.dig("media", "track"),
      payload: payload.dig("media", "payload")
    )
  end

  def conversation_for_call(call_sid)
    call_event = CallEvent.find_by(twilio_call_sid: call_sid)
    call_event&.conversation
  end

  def openai_realtime_stream?(conversation, payload)
    custom_parameters = payload.dig("start", "customParameters") || {}
    provider = custom_parameters["provider"].presence || conversation.call_state&.provider

    provider.to_s == "openai_realtime"
  end

  def valid_stream_token?(conversation, payload)
    expected = conversation.call_state&.state.to_h["twilio_stream_token"].to_s
    provided = stream_token_from(payload).to_s
    return false if expected.blank? || provided.blank?
    return false unless expected.bytesize == provided.bytesize

    ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end

  def stream_token_from(payload)
    custom_parameters = payload.dig("start", "customParameters") || {}
    custom_parameters["stream_token"] || custom_parameters["twilio_stream_token"]
  end

  def record_rejected_start(conversation, call_sid, payload)
    conversation.call_events.create!(
      twilio_call_sid: call_sid,
      status: "twilio_stream_rejected",
      direction: "inbound",
      data: sanitized_stream_payload(payload).merge("reason" => "invalid_stream_token")
    )
  rescue StandardError => error
    Rails.logger.warn("[TwilioMediaStream] rejected start #{error.class}: #{error.message}")
  end

  def sanitized_stream_payload(payload)
    JSON.parse(JSON.generate(payload)).tap do |copy|
      custom_parameters = copy.dig("start", "customParameters")
      custom_parameters.delete("stream_token") if custom_parameters.is_a?(Hash)
      custom_parameters.delete("twilio_stream_token") if custom_parameters.is_a?(Hash)
    end
  end

  def close_socket(ws)
    ws&.close(1008, "Invalid stream token")
  rescue StandardError
    nil
  end

  def start_openai_realtime_bridge(ws, conversation, call_sid, stream_sid, payload)
    return if ws.blank? || stream_sid.blank?
    return if realtime_bridges[stream_sid].present?

    custom_parameters = payload.dig("start", "customParameters") || {}
    agent_setting = AgentSetting.find_by(id: custom_parameters["agent_setting_id"]) ||
      AgentSetting.find_by(agent_id: custom_parameters["agent_id"])

    realtime_bridges[stream_sid] = OpenaiRealtimeTwilioBridge.new(
      twilio_ws: ws,
      conversation: conversation,
      call_sid: call_sid,
      stream_sid: stream_sid,
      agent_setting: agent_setting,
      custom_parameters: custom_parameters
    ).start
  end

  def close_realtime_bridge(stream_sid)
    bridge = realtime_bridges.delete(stream_sid)
    bridge&.close
  end

  def close_bridges_for_socket(ws)
    realtime_bridges.delete_if do |_stream_sid, bridge|
      next false unless bridge.twilio_ws == ws

      bridge.close
      true
    end
  end

  def record_media_frame(stream_sid, payload)
    return if stream_sid.blank?
    return unless stream_recordings.key?(stream_sid)

    frames = stream_recordings[stream_sid]
    return if frames.size >= MAX_FRAMES_PER_STREAM

    media = payload["media"] || {}
    audio = media["payload"]
    return if audio.blank?

    frames << {
      timestamp: media["timestamp"].to_i,
      track: media["track"],
      payload: audio
    }
  end

  def attach_recording(conversation, call_sid, frames)
    wav = wav_from_frames(frames)
    return if wav.blank?

    conversation.recording.purge if conversation.recording.attached?
    conversation.recording.attach(
      io: StringIO.new(wav),
      filename: "twilio-call-#{call_sid}-#{Time.current.to_i}.wav",
      content_type: "audio/wav"
    )

    conversation.call_events.create!(
      twilio_call_sid: call_sid,
      status: "twilio_stream_recording",
      direction: "inbound",
      data: {
        source: "twilio_media_stream",
        format: "audio/wav",
        sample_rate: SAMPLE_RATE,
        frames: frames.size,
        byte_size: wav.bytesize
      }
    )
  end

  def wav_from_frames(frames)
    samples = pcm_samples_from_frames(frames)
    return if samples.blank?

    pcm = samples.pack("s<*")
    [
      "RIFF",
      [ 36 + pcm.bytesize ].pack("V"),
      "WAVE",
      "fmt ",
      [ 16 ].pack("V"),
      [ 1 ].pack("v"),
      [ 1 ].pack("v"),
      [ SAMPLE_RATE ].pack("V"),
      [ SAMPLE_RATE * 2 ].pack("V"),
      [ 2 ].pack("v"),
      [ 16 ].pack("v"),
      "data",
      [ pcm.bytesize ].pack("V"),
      pcm
    ].join.b
  end

  def pcm_samples_from_frames(frames)
    indexed_frames = frames.each_with_index.map do |frame, index|
      frame.merge(timestamp: frame[:timestamp].presence || index)
    end

    indexed_frames
      .group_by { |frame| frame[:timestamp] }
      .sort_by { |timestamp, _group| timestamp }
      .flat_map do |_timestamp, group|
        mix_samples(group.map { |frame| decode_mulaw_payload(frame[:payload]) })
      end
  end

  def mix_samples(sample_sets)
    sample_sets = sample_sets.reject(&:blank?)
    return [] if sample_sets.blank?
    return sample_sets.first if sample_sets.one?

    length = sample_sets.map(&:length).max
    Array.new(length) do |index|
      value = sample_sets.sum { |samples| samples[index].to_i }
      clamp_pcm(value)
    end
  end

  def decode_mulaw_payload(payload)
    Base64.decode64(payload.to_s).bytes.map { |byte| mulaw_to_pcm(byte) }
  rescue ArgumentError
    []
  end

  def mulaw_to_pcm(byte)
    byte = (~byte) & 0xff
    sign = byte & 0x80
    exponent = (byte >> 4) & 0x07
    mantissa = byte & 0x0f
    sample = (((mantissa << 3) + 0x84) << exponent) - 0x84
    sign.zero? ? sample : -sample
  end

  def clamp_pcm(value)
    [ [ value, -32_768 ].max, 32_767 ].min
  end
end
