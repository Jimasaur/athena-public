require "securerandom"

class TwilioRegisterController < ApplicationController
  REALTIME_PROVIDER = "openai_realtime"

  skip_before_action :verify_authenticity_token
  before_action :verify_twilio_signature!, if: :twilio_signature_verification_enabled?

  def inbound
    return render plain: (@twilio_register_error || "Caller not allowed"), status: :forbidden unless inbound_caller_allowed?

    twiml = register_call_twiml(direction: "inbound")
    return render plain: (@twilio_register_error || "Failed to build TwiML"), status: :bad_request if twiml.blank?

    set_twiml_headers(twiml)
    render plain: twiml
  end

  def outbound
    twiml = register_call_twiml(direction: "outbound")
    return render plain: (@twilio_register_error || "Failed to build TwiML"), status: :bad_request if twiml.blank?

    set_twiml_headers(twiml)
    render plain: twiml
  end

  def transcription
    call_sid = params["CallSid"]
    return head :bad_request if call_sid.blank?

    conversation = find_conversation_by_call_sid(call_sid)
    return head :ok if conversation.blank?
    return head :ok if conversation.transcript_call_event_id.present?

    text = transcription_text
    return head :ok if text.blank?

    role = transcription_role
    sent_at = transcription_timestamp || Time.current
    log_transcription_debug(call_sid, text, role)
    create_message_unless_exists(conversation, role: role, content: text, sent_at: sent_at)

    head :ok
  end

  def status
    call_sid = params["CallSid"]
    return head :bad_request if call_sid.blank?

    conversation = find_conversation_by_call_sid(call_sid)
    return head :ok if conversation.blank?

    conversation.call_events.create!(
      twilio_call_sid: call_sid,
      status: params["CallStatus"] || "status",
      direction: params["Direction"] || "inbound",
      from_number: params["From"],
      to_number: params["To"],
      data: twilio_status_payload
    )
    sync_twilio_status!(conversation, params["CallStatus"])
    run_completed_call_sidecars(conversation, params["CallStatus"])

    head :ok
  end

  private

  def register_call_twiml(direction:)
    call_sid = params["CallSid"]
    from_number = params["From"]
    to_number = params["To"] || params["Called"]

    agent_setting = agent_setting_for(to_number)
    if agent_setting.blank?
      @twilio_register_error = "No matching Realtime agent profile found for this call"
      return
    end

    conversation = ensure_call_event(call_sid, from_number, to_number, direction, agent_setting, provider: REALTIME_PROVIDER)
    openai_realtime_twiml(conversation, agent_setting, from_number, to_number, call_sid)
  rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error
    @twilio_register_error = "Timed out building OpenAI Realtime TwiML"
    nil
  rescue StandardError => error
    @twilio_register_error = error.message
    nil
  end

  def openai_realtime_twiml(conversation, agent_setting, from_number, to_number, call_sid)
    stream_url = twilio_stream_url
    stream_token = twilio_stream_token_for(conversation)

    Twilio::TwiML::VoiceResponse.new do |response|
      if twilio_realtime_transcription_enabled?
        response.start do |start|
          start.transcription(
            status_callback_url: twilio_transcription_url,
            track: "both",
            inbound_track_label: "user",
            outbound_track_label: "agent"
          )
        end
      end
      response.connect do |connect|
        connect.stream(url: stream_url) do |stream|
          stream.parameter(name: "provider", value: "openai_realtime")
          stream.parameter(name: "conversation_id", value: conversation.id)
          stream.parameter(name: "call_sid", value: call_sid) if call_sid.present?
          stream.parameter(name: "agent_setting_id", value: agent_setting.id) if agent_setting.present?
          stream.parameter(name: "agent_name", value: agent_setting.name) if agent_setting&.name.present?
          stream.parameter(name: "from_number", value: from_number) if from_number.present?
          stream.parameter(name: "to_number", value: to_number) if to_number.present?
          stream.parameter(name: "stream_token", value: stream_token) if stream_token.present?
        end
      end
    end.to_s
  end

  def twilio_transcription_url
    "#{public_base_url}#{twilio_transcription_webhook_path}"
  end

  def twilio_realtime_transcription_enabled?
    ActiveModel::Type::Boolean.new.cast(AppSetting.fetch("OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED", false))
  end

  def twilio_stream_url
    build_ws_url("/ws/twilio-media")
  end

  def ensure_call_event(call_sid, from_number, to_number, direction, agent_setting, provider: REALTIME_PROVIDER)
    return if call_sid.blank?

    target_number = direction == "outbound" ? to_number : from_number
    phone_number = target_number.presence || "unknown-#{call_sid}"
    customer = Customer.find_or_create_by!(phone_number: phone_number) do |record|
      record.name = "Unknown caller"
    end

    conversation = Conversation.find_or_create_by!(twilio_call_sid: call_sid) do |record|
      record.customer = customer
      record.channel = "voice"
      record.status = "in_progress"
      record.agent_name = agent_setting&.name
    end

    conversation.call_events.find_or_create_by!(twilio_call_sid: call_sid) do |event|
      event.status = "in_progress"
      event.direction = direction
      event.from_number = from_number
      event.to_number = to_number
      event.data = { source: "twilio_register", agent_id: agent_setting&.agent_id, provider: provider }
    end

    CallState.ensure_for_conversation(
      conversation,
      provider: provider,
      call_id: call_sid,
      status: "active"
    )

    conversation
  end

  def twilio_stream_token_for(conversation)
    call_state = conversation.call_state ||
      CallState.ensure_for_conversation(
        conversation,
        provider: REALTIME_PROVIDER,
        call_id: conversation.twilio_call_sid || "conversation-#{conversation.id}",
        status: conversation.status == "completed" ? "completed" : "active"
      )
    state = call_state.state.to_h
    token = state["twilio_stream_token"].presence || SecureRandom.urlsafe_base64(32)

    call_state.update!(
      state: state.merge(
        "twilio_stream_token" => token,
        "twilio_stream_token_created_at" => Time.current.iso8601
      )
    )
    token
  end

  def sync_twilio_status!(conversation, status)
    normalized = normalized_twilio_status(status)
    return if normalized.blank?

    conversation.update!(status: normalized)
    conversation.call_state&.update!(status: normalized == "in_progress" ? "active" : normalized)
  end

  def normalized_twilio_status(status)
    status = status.to_s.downcase.tr("-", "_")
    return if status.blank?

    return "in_progress" if %w[queued ringing initiated in_progress].include?(status)
    return "completed" if status == "completed"
    return "failed" if %w[busy canceled cancelled failed no_answer].include?(status)

    status
  end

  def run_completed_call_sidecars(conversation, status)
    return unless normalized_twilio_status(status) == "completed"

    AthenaIdeaCaptureService.new(conversation: conversation).call
    AthenaEmailApprovalSidecarService.new(conversation: conversation).call
    AthenaTranscriptEmailJob.set(wait: transcript_email_delay_seconds.seconds).perform_later(conversation.id)
  rescue StandardError => error
    Rails.logger.warn("[AthenaCompletedCallSidecars] #{error.class}: #{error.message}")
  end

  def transcript_email_delay_seconds
    configured = AppSetting.fetch("ATHENA_TRANSCRIPT_EMAIL_DELAY_SECONDS").to_i
    configured.positive? ? configured : 45
  end

  def agent_setting_for(to_number)
    agent_id = params["AgentId"] || params["AgentID"] || params["agent_id"]
    if agent_id.present?
      return AgentSetting.find_by(agent_id: agent_id)
    end

    normalized_to = normalize_phone(to_number)
    if normalized_to.present?
      matched = AgentSetting.where.not(twilio_number: nil).detect do |setting|
        normalize_phone(setting.twilio_number) == normalized_to
      end
      return matched if matched.present?
    end

    AgentSetting.order(:id).first
  end

  def normalize_phone(value)
    digits = value.to_s.gsub(/\D/, "")
    return if digits.blank?

    digits = digits.sub(/^1(?=\d{10}$)/, "")
    digits.presence
  end

  def find_conversation_by_call_sid(call_sid)
    found = Conversation.find_by(twilio_call_sid: call_sid)
    return found if found.present?

    call_event = CallEvent.find_by(twilio_call_sid: call_sid)
    call_event&.conversation
  end

  def transcription_text
    params["TranscriptionText"] ||
      params["transcriptionText"] ||
      params["SpeechResult"] ||
      params["utterance"] ||
      params["Utterance"] ||
      params["Transcript"] ||
      parse_transcription_data
  end

  def log_transcription_debug(call_sid, text, role)
    # no-op
  end

  def transcription_role
    TranscriptRoleNormalizer.call(
      params["TrackLabel"] ||
        params["trackLabel"] ||
        params["ParticipantRole"] ||
        params["participantRole"] ||
        params["Speaker"] ||
        params["speaker"] ||
        params["Role"] ||
        params["role"] ||
        params["Track"] ||
        params["track"]
    )
  end

  def transcription_timestamp
    timestamp = params["Timestamp"] || params["timestamp"]
    return if timestamp.blank?

    Time.zone.parse(timestamp.to_s)
  rescue ArgumentError
    nil
  end

  def parse_transcription_data
    raw = params["TranscriptionData"]
    return if raw.blank?

    parsed = JSON.parse(raw)
    parsed["transcript"]
  rescue JSON::ParserError
    nil
  end

  def create_message_unless_exists(conversation, role:, content:, sent_at:)
    exists = conversation.messages.where(role: role, content: content, sent_at: sent_at).exists?
    return if exists

    conversation.messages.create!(role: role, content: content, sent_at: sent_at)
  end

  def set_twiml_headers(twiml)
    response.headers["Content-Type"] = "application/xml"
    response.headers["Content-Length"] = twiml.to_s.bytesize.to_s
    response.headers["Connection"] = "close"
  end

  def public_base_url
    configured = AppSetting.fetch("PUBLIC_BASE_URL").to_s.strip
    return configured if configured.present?

    request.base_url
  end

  def build_ws_url(path)
    uri = URI.parse(public_base_url)
    uri.scheme = uri.scheme == "https" ? "wss" : "ws"
    uri.path = path
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  end

  def inbound_caller_allowed?
    allowed = allowed_inbound_callers
    return true if allowed.blank?

    allowed.include?(normalize_phone(params["From"]))
  end

  def allowed_inbound_callers
    raw = AppSetting.fetch("TWILIO_ALLOWED_CALLERS").to_s
    raw.split(/[,\s]+/).map { |value| normalize_phone(value) }.compact.uniq
  end

  def twilio_signature_verification_enabled?
    ActiveModel::Type::Boolean.new.cast(AppSetting.fetch("TWILIO_VERIFY_WEBHOOK_SIGNATURES"))
  end

  def verify_twilio_signature!
    auth_token = AppSetting.fetch("TWILIO_AUTH_TOKEN").to_s
    signature = request.headers["X-Twilio-Signature"].to_s
    return head :unauthorized if auth_token.blank? || signature.blank?

    validator = Twilio::Security::RequestValidator.new(auth_token)
    return if validator.validate(twilio_signature_url, twilio_signature_params, signature)

    head :unauthorized
  end

  def twilio_signature_url
    base_url = AppSetting.fetch("PUBLIC_BASE_URL").to_s.strip
    url = base_url.present? ? "#{base_url}#{request.path}" : request.original_url
    request.query_string.present? ? "#{url}?#{request.query_string}" : url
  end

  def twilio_signature_params
    params.to_unsafe_h.except("controller", "action")
  end

  def twilio_status_payload
    params.to_unsafe_h.slice(
      "CallSid",
      "CallStatus",
      "Direction",
      "From",
      "To",
      "Timestamp",
      "ApiVersion"
    )
  end
end
