require "faye/websocket"
require "json"
require "net/http"
require "uri"

class OpenaiRealtimeTwilioBridge
  DEFAULT_MODEL = "gpt-realtime-1.5"
  DEFAULT_VOICE = "marin"
  DEFAULT_TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe"
  DEFAULT_INPUT_NOISE_REDUCTION = "near_field"
  DEFAULT_TURN_DETECTION_TYPE = "server_vad"
  DEFAULT_VAD_THRESHOLD = 0.65
  DEFAULT_VAD_PREFIX_PADDING_MS = 300
  DEFAULT_VAD_SILENCE_DURATION_MS = 500
  DEFAULT_VAD_IDLE_TIMEOUT_MS = 6_000
  DEFAULT_SEMANTIC_EAGERNESS = "auto"
  DEFAULT_CREATE_RESPONSE = true
  DEFAULT_INTERRUPT_RESPONSE = false
  DEFAULT_INTERRUPT_GRACE_MS = 2_500
  OPENAI_WS_URL = "wss://api.openai.com/v1/realtime"
  TOOL_TIMEOUT_SECONDS = 8

  attr_reader :twilio_ws

  def initialize(twilio_ws:, conversation:, call_sid:, stream_sid:, agent_setting: nil, custom_parameters: {})
    @twilio_ws = twilio_ws
    @conversation = conversation
    @call_sid = call_sid
    @stream_sid = stream_sid
    @agent_setting = agent_setting
    @custom_parameters = custom_parameters || {}
    @pending_audio = []
    @closed = false
  end

  def start
    if openai_api_key.blank?
      record_event("openai_realtime_missing_api_key", error: "OPENAI_API_KEY is missing.")
      close_twilio
      return self
    end

    @openai_ws = Faye::WebSocket::Client.new(
      openai_url,
      nil,
      headers: { "Authorization" => "Bearer #{openai_api_key}" }
    )
    @openai_ws.on(:open) { handle_openai_open }
    @openai_ws.on(:message) { |event| handle_openai_message(event.data) }
    @openai_ws.on(:error) { |event| handle_openai_error(event) }
    @openai_ws.on(:close) { |event| handle_openai_close(event) }
    self
  rescue StandardError => error
    record_event("openai_realtime_bridge_error", error: "#{error.class}: #{error.message}")
    close_twilio
    self
  end

  def receive_twilio_media(payload)
    audio = payload.dig("media", "payload")
    return if audio.blank?

    if openai_open?
      send_openai(input_audio_append_event(audio))
    elsif @pending_audio.size < 100
      @pending_audio << audio
    end
  end

  def close
    return if @closed

    @closed = true
    @openai_ws&.close
  end

  private

  def handle_openai_open
    @connected_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    record_event("openai_realtime_connected", model: realtime_model, voice: realtime_voice)
    send_openai(session_update_event)
    flush_pending_audio
    send_openai(type: "response.create")
  end

  def handle_openai_message(raw)
    event = JSON.parse(raw)

    case event["type"]
    when "response.output_audio.delta", "response.audio.delta"
      forward_openai_audio(event["delta"])
    when "input_audio_buffer.speech_started"
      handle_speech_started(event)
    when "conversation.item.input_audio_transcription.completed"
      create_transcript_message("user", event["transcript"])
    when "response.output_audio_transcript.done", "response.audio_transcript.done"
      create_transcript_message("assistant", event["transcript"])
    when "response.done"
      handle_response_done(event)
    when "error"
      record_event("openai_realtime_error", payload: event)
    end
  rescue JSON::ParserError
    record_event("openai_realtime_invalid_json", raw: raw.to_s.truncate(500))
  rescue StandardError => error
    record_event("openai_realtime_message_error", error: "#{error.class}: #{error.message}")
  end

  def handle_response_done(event)
    Array(event.dig("response", "output")).each do |item|
      next unless item["type"] == "function_call"

      handle_function_call(item)
    end
  end

  def handle_function_call(item)
    return unless item["name"] == "athena_command"

    arguments = parse_json_object(item["arguments"])
    result = call_athena_command(arguments)

    send_openai(
      type: "conversation.item.create",
      item: {
        type: "function_call_output",
        call_id: item["call_id"],
        output: result.to_json
      }
    )
    send_openai(type: "response.create")

    record_event(
      "openai_realtime_function_call",
      function: item["name"],
      call_id: item["call_id"],
      arguments: arguments,
      result: logged_tool_result(result)
    )
  end

  def call_athena_command(arguments)
    url = athena_command_url
    return { ok: false, error: "ATHENA_INTERNAL_BASE_URL or PUBLIC_BASE_URL is required for Realtime tool calls." } if url.blank?

    payload = {
      command: arguments["command"].presence || "semantic_request",
      request: arguments["request"].presence || arguments["query"].presence || arguments["message"].presence,
      conversation_id: @conversation.id,
      call_sid: @call_sid
    }.compact

    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Athena-Tool-Secret"] = tool_secret if tool_secret.present?
    request.body = payload.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 2
    http.read_timeout = TOOL_TIMEOUT_SECONDS

    response = http.request(request)
    JSON.parse(response.body).merge("status" => response.code.to_i)
  rescue JSON::ParserError
    { ok: false, error: "Athena command returned invalid JSON." }
  rescue StandardError => error
    { ok: false, error: "Athena command failed: #{error.message}" }
  end

  def session_update_event
    session = {
      type: "realtime",
      model: realtime_model,
      instructions: realtime_instructions,
      output_modalities: [ "audio" ],
      audio: {
        input: {
          format: { type: "audio/pcmu" },
          noise_reduction: realtime_noise_reduction,
          transcription: realtime_transcription,
          turn_detection: realtime_turn_detection
        },
        output: {
          format: { type: "audio/pcmu" },
          voice: realtime_voice
        }
      },
      tools: [ athena_command_tool ],
      tool_choice: "auto"
    }

    overrides = realtime_session_overrides
    session = session.deep_merge(overrides.deep_symbolize_keys) if overrides.present?

    {
      type: "session.update",
      session: session
    }
  end

  def athena_command_tool
    {
      type: "function",
      name: "athena_command",
      description: "Call Athena for status, web search, weather, contact lookup, call summaries, rev-cycle idea capture, or approval-gated email handoff.",
      parameters: {
        type: "object",
        properties: {
          command: {
            type: "string",
            description: "Use semantic_request for natural language requests unless a more specific command is obvious.",
            enum: [
              "semantic_request",
              "status",
              "web_search",
              "capture_idea",
              "find_contact",
              "summarize_last_call",
              "email"
            ]
          },
          request: {
            type: "string",
            description: "The caller's request, rewritten clearly and briefly for Athena."
          }
        },
        required: [ "command", "request" ],
        additionalProperties: false
      }
    }
  end

  def realtime_instructions
    base = @agent_setting&.system_prompt.presence || <<~PROMPT.squish
      You are Athena, a healthcare revenue cycle ideation partner. You are on a live phone call.
    PROMPT
    first_greeting = @agent_setting&.first_message.to_s.squish.presence || "Welcome to the rev cycle ideas line. I'm Athena. I can help you think through big ideas or small fixes for the retreat. We'll keep it simple: tell me the issue, what might help, and what outcome you want. Please avoid patient names or MRNs. What idea should we work on first?"

    <<~PROMPT.squish
      #{base}
      Open the call exactly once with: "#{first_greeting}"
      Do not repeat or restate the greeting, safety note, or opening question.
      If the opening is interrupted, continue naturally instead of restarting the full greeting.
      Speak the opening at a calm, measured pace with brief pauses between sentences.
      Speak in short phone-friendly turns, usually one or two sentences.
      Ask one question at a time.
      Guide each idea through problem, proposed change, impact, risks or constraints, and next step.
      When one idea has enough detail, say that you have enough to save it, then ask: "Do you want to add another idea, refine this one, or are you done for now? If you're done, you can hang up."
      If the caller says they are done, briefly thank them and say it is okay to hang up.
      Use athena_command with capture_idea when the caller gives a meaningful healthcare revenue cycle automation, innovation, cost savings, or workflow improvement idea.
      Use athena_command when the caller asks for current information, weather, web search, call summaries, contacts, or email handoff.
      External side effects like sending email must go through Athena's approval workflow.
      If a tool result includes a reply field, use it as the basis for your spoken answer.
      For current information and weather, describe the source as Athena web search or Brave Search snippets unless the tool result names a more specific source.
      Do not invent specific source names, temperatures, citations, or tool capabilities that are not present in the tool result.
      Do not mention JSON, webhooks, sidecars, or internal tool names to the caller.
    PROMPT
  end

  def input_audio_append_event(audio)
    {
      type: "input_audio_buffer.append",
      audio: audio
    }
  end

  def flush_pending_audio
    @pending_audio.each { |audio| send_openai(input_audio_append_event(audio)) }
    @pending_audio.clear
  end

  def forward_openai_audio(delta)
    return if delta.blank?

    send_twilio(
      event: "media",
      streamSid: @stream_sid,
      media: {
        payload: delta
      }
    )
  end

  def clear_twilio_audio
    send_twilio(event: "clear", streamSid: @stream_sid)
  end

  def handle_speech_started(event)
    elapsed_ms = realtime_elapsed_ms
    should_clear = realtime_interrupt_response? && elapsed_ms >= realtime_interrupt_grace_ms

    record_event(
      "openai_realtime_speech_started",
      elapsed_ms: elapsed_ms,
      interrupt_response: realtime_interrupt_response?,
      interrupt_grace_ms: realtime_interrupt_grace_ms,
      cleared_twilio_audio: should_clear,
      audio_start_ms: event["audio_start_ms"]
    )

    clear_twilio_audio if should_clear
  end

  def create_transcript_message(role, transcript)
    content = transcript.to_s.squish
    return if content.blank?

    exists = @conversation.messages.where(role: role, content: content).exists?
    return if exists

    @conversation.messages.create!(role: role, content: content, sent_at: Time.current)
  end

  def handle_openai_error(event)
    record_event("openai_realtime_socket_error", error: event.respond_to?(:message) ? event.message : event.inspect)
  end

  def handle_openai_close(event)
    record_event("openai_realtime_closed", code: event.code, reason: event.reason)
    close_twilio unless @closed
  end

  def send_openai(payload)
    return unless openai_open?

    @openai_ws.send(payload.to_json)
  end

  def send_twilio(payload)
    return if @twilio_ws.blank?

    @twilio_ws.send(payload.to_json)
  end

  def close_twilio
    @twilio_ws&.close
  end

  def openai_open?
    @openai_ws&.ready_state == Faye::WebSocket::API::OPEN
  end

  def openai_url
    uri = URI.parse(OPENAI_WS_URL)
    uri.query = URI.encode_www_form(model: realtime_model)
    uri.to_s
  end

  def athena_command_url
    base = AppSetting.fetch("ATHENA_INTERNAL_BASE_URL").presence ||
      AppSetting.fetch("PUBLIC_BASE_URL").presence
    return if base.blank?

    URI.join(base, "/agent_tools/command").to_s
  rescue URI::InvalidURIError
    nil
  end

  def openai_api_key
    AppSetting.fetch("OPENAI_API_KEY").to_s.strip
  end

  def realtime_model
    AppSetting.fetch("OPENAI_REALTIME_MODEL", DEFAULT_MODEL).to_s.strip.presence || DEFAULT_MODEL
  end

  def realtime_voice
    @agent_setting&.voice_id.to_s.strip.presence ||
      AppSetting.fetch("OPENAI_REALTIME_VOICE", DEFAULT_VOICE).to_s.strip.presence ||
      DEFAULT_VOICE
  end

  def realtime_transcription_model
    setting_text("OPENAI_REALTIME_TRANSCRIPTION_MODEL", DEFAULT_TRANSCRIPTION_MODEL)
  end

  def realtime_transcription
    return nil if disabled_setting?(realtime_transcription_model)

    { model: realtime_transcription_model }
  end

  def realtime_noise_reduction
    value = setting_text("OPENAI_REALTIME_INPUT_NOISE_REDUCTION", DEFAULT_INPUT_NOISE_REDUCTION).downcase
    return nil if disabled_setting?(value)

    { type: %w[near_field far_field].include?(value) ? value : DEFAULT_INPUT_NOISE_REDUCTION }
  end

  def realtime_turn_detection
    type = setting_text("OPENAI_REALTIME_TURN_DETECTION_TYPE", DEFAULT_TURN_DETECTION_TYPE).downcase
    return nil if disabled_setting?(type)

    type = DEFAULT_TURN_DETECTION_TYPE unless %w[server_vad semantic_vad].include?(type)

    turn_detection = {
      type: type,
      create_response: realtime_boolean("OPENAI_REALTIME_CREATE_RESPONSE", DEFAULT_CREATE_RESPONSE),
      interrupt_response: realtime_interrupt_response?
    }

    if type == "semantic_vad"
      eagerness = setting_text("OPENAI_REALTIME_SEMANTIC_EAGERNESS", DEFAULT_SEMANTIC_EAGERNESS).downcase
      turn_detection[:eagerness] = %w[auto low medium high].include?(eagerness) ? eagerness : DEFAULT_SEMANTIC_EAGERNESS
    else
      turn_detection[:threshold] = realtime_float("OPENAI_REALTIME_VAD_THRESHOLD", DEFAULT_VAD_THRESHOLD, min: 0, max: 1)
      turn_detection[:prefix_padding_ms] = realtime_integer("OPENAI_REALTIME_VAD_PREFIX_PADDING_MS", DEFAULT_VAD_PREFIX_PADDING_MS, min: 0)
      turn_detection[:silence_duration_ms] = realtime_integer("OPENAI_REALTIME_VAD_SILENCE_DURATION_MS", DEFAULT_VAD_SILENCE_DURATION_MS, min: 0)
      turn_detection[:idle_timeout_ms] = realtime_integer("OPENAI_REALTIME_VAD_IDLE_TIMEOUT_MS", DEFAULT_VAD_IDLE_TIMEOUT_MS, min: 0)
    end

    turn_detection
  end

  def realtime_interrupt_response?
    realtime_boolean("OPENAI_REALTIME_INTERRUPT_RESPONSE", DEFAULT_INTERRUPT_RESPONSE)
  end

  def realtime_interrupt_grace_ms
    realtime_integer("OPENAI_REALTIME_INTERRUPT_GRACE_MS", DEFAULT_INTERRUPT_GRACE_MS, min: 0)
  end

  def realtime_session_overrides
    raw = AppSetting.fetch("OPENAI_REALTIME_SESSION_OVERRIDES_JSON").to_s.strip
    return {} if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError => error
    record_event("openai_realtime_session_overrides_invalid", error: error.message)
    {}
  end

  def realtime_elapsed_ms
    return 0 if @connected_at.blank?

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @connected_at) * 1000).round
  end

  def setting_text(key, default = nil)
    AppSetting.fetch(key).to_s.strip.presence || default.to_s
  end

  def realtime_boolean(key, default)
    value = AppSetting.fetch(key).to_s.strip.downcase
    return default if value.blank?
    return true if %w[1 true yes on enabled].include?(value)
    return false if %w[0 false no off disabled].include?(value)

    default
  end

  def realtime_integer(key, default, min: nil, max: nil)
    value = Integer(AppSetting.fetch(key).to_s.strip)
    value = [ value, min ].max if min
    value = [ value, max ].min if max
    value
  rescue ArgumentError, TypeError
    default
  end

  def realtime_float(key, default, min: nil, max: nil)
    value = Float(AppSetting.fetch(key).to_s.strip)
    value = [ value, min ].max if min
    value = [ value, max ].min if max
    value
  rescue ArgumentError, TypeError
    default
  end

  def disabled_setting?(value)
    %w[none null off false disabled manual].include?(value.to_s.strip.downcase)
  end

  def tool_secret
    AppSetting.fetch("ATHENA_TOOL_SECRET").to_s
  end

  def parse_json_object(value)
    parsed = JSON.parse(value.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def logged_tool_result(result)
    normalized = result.to_h.with_indifferent_access
    summary = normalized.slice(:ok, :command, :intent, :action, :provider, :status, :error, :query)
    summary[:reply] = normalized[:reply].to_s.truncate(500) if normalized[:reply].present?
    summary[:results_count] = Array(normalized[:results]).size if normalized.key?(:results)
    summary
  end

  def record_event(kind, payload = {})
    @conversation.call_events.create!(
      twilio_call_sid: @call_sid,
      status: kind,
      direction: "inbound",
      data: payload.compact
    )
  rescue StandardError => error
    Rails.logger.warn("[OpenAIRealtimeTwilioBridge] #{kind} #{error.class}: #{error.message}")
  end
end
