class ActionDraftExecutionService
  Result = Struct.new(:ok, :action_draft, :error, keyword_init: true)

  TWILIO_PROVIDER = "twilio"
  EMAIL_PROVIDER = "gemma_mail"

  attr_reader :action_draft, :executor

  def initialize(action_draft:, executor: "admin")
    @action_draft = action_draft
    @executor = executor.to_s.presence || "admin"
  end

  def call
    error = nil

    action_draft.with_lock do
      if !action_draft.executable?
        error = "Draft must be approved before it can be executed."
      elsif action_draft.kind == "follow_up_message"
        error = send_sms
      elsif action_draft.kind == "email"
        error = send_email
      else
        error = "Only follow-up message and email drafts can be sent right now."
      end
    end

    return Result.new(ok: false, action_draft: action_draft, error: error) if error.present?

    Result.new(ok: true, action_draft: action_draft)
  end

  private

  def send_email
    return complete_email_dry_run if dry_run?

    payload = email_payload
    return fail_email_execution("Draft recipient is missing an email address.") if payload[:to].blank?
    return fail_email_execution("Draft subject is blank.") if payload[:subject].blank?
    return fail_email_execution("Draft body is blank.") if payload[:body].blank?

    result = GemmaMailAgentService.new(payload: payload).call
    return fail_email_execution(result[:error].presence || "Gemma Mail could not process the email.") unless result[:ok]

    unless result[:delivery_status] == "sent"
      detail = result[:reply].presence || "Gemma Mail did not confirm delivery."
      return fail_email_execution("Gemma Mail did not confirm the email was sent. #{detail}")
    end

    action_draft.mark_executed!(
      provider: EMAIL_PROVIDER,
      external_id: result.dig(:meta, "message_id")
    )
    remember_email_result(result)
    create_event(
      kind: "external_action.executed",
      source: "gemma_mail_executor",
      provider: EMAIL_PROVIDER,
      payload: execution_payload(
        provider: EMAIL_PROVIDER,
        to: payload[:to],
        subject: payload[:subject],
        action: result[:action],
        delivery_status: result[:delivery_status],
        reply: result[:reply]
      )
    )

    nil
  rescue StandardError => error
    fail_email_execution(error.message)
  end

  def send_sms
    return complete_dry_run if dry_run?

    account_sid = AppSetting.fetch("TWILIO_ACCOUNT_SID").to_s.strip
    auth_token = AppSetting.fetch("TWILIO_AUTH_TOKEN").to_s.strip
    return fail_execution("Missing TWILIO_ACCOUNT_SID or TWILIO_AUTH_TOKEN.") if account_sid.blank? || auth_token.blank?

    messaging_service_sid = resolved_messaging_service_sid
    from_number = resolved_from_number
    to_number = action_draft.recipient&.dig("phone").to_s.strip
    body = action_draft.content&.dig("body").to_s.strip

    return fail_execution("Missing Twilio SMS from number or TWILIO_MESSAGING_SERVICE_SID.") if messaging_service_sid.blank? && from_number.blank?
    return fail_execution("Draft recipient is missing a phone number.") if to_number.blank?
    return fail_execution("Draft body is blank.") if body.blank?
    return fail_execution("Recipient is marked do-not-contact or opted out of SMS.") if sms_blocked_recipient?(to_number)

    send_params = {
      to: to_number,
      body: body
    }
    if messaging_service_sid.present?
      send_params[:messaging_service_sid] = messaging_service_sid
    else
      send_params[:from] = from_number
    end

    message = Twilio::REST::Client.new(account_sid, auth_token).messages.create(send_params)

    action_draft.mark_executed!(provider: TWILIO_PROVIDER, external_id: message.sid)
    create_event(
      kind: "external_action.executed",
      source: "twilio_sms_executor",
      provider: TWILIO_PROVIDER,
      payload: execution_payload(
        provider: TWILIO_PROVIDER,
        from_number: from_number,
        messaging_service_sid: messaging_service_sid,
        to_number: to_number,
        twilio_message_sid: message.sid
      )
    )

    nil
  rescue StandardError => error
    fail_execution(error.message)
  end

  def complete_dry_run
    external_id = "SM-DEMO-#{action_draft.id}"
    action_draft.mark_executed!(provider: "demo_twilio", external_id: external_id)
    create_event(
      kind: "external_action.executed",
      source: "twilio_sms_executor",
      provider: "demo_twilio",
      payload: execution_payload(
        provider: "demo_twilio",
        twilio_message_sid: external_id,
        mode: "demo",
        dry_run: true
      )
    )

    nil
  end

  def complete_email_dry_run
    external_id = "EMAIL-DEMO-#{action_draft.id}"
    action_draft.mark_executed!(provider: "demo_gemma_mail", external_id: external_id)
    create_event(
      kind: "external_action.executed",
      source: "gemma_mail_executor",
      provider: "demo_gemma_mail",
      payload: execution_payload(
        provider: "demo_gemma_mail",
        external_id: external_id,
        mode: "demo",
        dry_run: true,
        to: action_draft.recipient&.dig("email"),
        subject: action_draft.content&.dig("subject")
      )
    )

    nil
  end

  def fail_execution(message)
    action_draft.mark_execution_failed!(provider: TWILIO_PROVIDER, error: message)
    create_event(
      kind: "external_action.failed",
      source: "twilio_sms_executor",
      provider: TWILIO_PROVIDER,
      payload: execution_payload(provider: TWILIO_PROVIDER, error: message),
      requires_review: true
    )
    message
  end

  def fail_email_execution(message)
    action_draft.mark_execution_failed!(provider: EMAIL_PROVIDER, error: message)
    create_event(
      kind: "external_action.failed",
      source: "gemma_mail_executor",
      provider: EMAIL_PROVIDER,
      payload: execution_payload(provider: EMAIL_PROVIDER, error: message),
      requires_review: true
    )
    message
  end

  def email_payload
    recipient = action_draft.recipient || {}
    content = action_draft.content || {}
    {
      to: recipient["email"].to_s.strip,
      cc: recipient["cc"].presence,
      bcc: recipient["bcc"].presence,
      subject: content["subject"].to_s.strip,
      body: content["body"].to_s.strip,
      request: content["request"].presence,
      conversation_id: action_draft.conversation_id,
      call_sid: action_draft.conversation.twilio_call_sid,
      draft_id: action_draft.id,
      mode: "send",
      send: true
    }.compact
  end

  def remember_email_result(result)
    side_effect = (action_draft.external_side_effect || {}).merge(
      "agent" => result[:agent],
      "session_id" => result[:session_id],
      "action" => result[:action],
      "delivery_status" => result[:delivery_status],
      "reply" => result[:reply]
    ).compact
    action_draft.update!(external_side_effect: side_effect)
  end

  def resolved_from_number
    configured_from_number.presence ||
      matching_agent_twilio_number.presence ||
      AppSetting.fetch("VOICEBOT_TWILIO_FROM_NUMBER").to_s.strip.presence ||
      AgentSetting.where.not(twilio_number: [ nil, "" ]).order(:id).pick(:twilio_number).to_s.strip.presence ||
      latest_call_agent_number.presence
  end

  def configured_from_number
    AppSetting.fetch("TWILIO_SMS_FROM_NUMBER").to_s.strip.presence ||
      AppSetting.fetch("TWILIO_FROM_NUMBER").to_s.strip.presence
  end

  def resolved_messaging_service_sid
    AppSetting.fetch("TWILIO_MESSAGING_SERVICE_SID").to_s.strip.presence
  end

  def latest_call_agent_number
    action_draft.conversation.call_events
      .where.not(to_number: [ nil, "" ])
      .order(created_at: :desc)
      .pick(:to_number)
      .to_s
      .strip
  end

  def matching_agent_twilio_number
    number = latest_call_agent_number
    return if number.blank?

    AgentSetting.where(twilio_number: number).pick(:twilio_number).to_s.strip.presence
  end

  def sms_blocked_recipient?(to_number)
    customer = action_draft.conversation.customer || Customer.find_by(phone_number: to_number)
    metadata = customer&.metadata || {}

    truthy_metadata?(metadata["sms_opt_out"]) ||
      truthy_metadata?(metadata["do_not_contact"]) ||
      truthy_metadata?(metadata["do_not_sms"]) ||
      metadata["sms_consent"] == false
  end

  def truthy_metadata?(value)
    value == true || value.to_s.strip.downcase.in?([ "true", "1", "yes", "y" ])
  end

  def execution_payload(extra = {})
    provider = extra[:provider] || extra["provider"] || TWILIO_PROVIDER

    {
      "action_draft_id" => action_draft.id,
      "action_kind" => action_draft.kind,
      "executor" => executor,
      "provider" => provider,
      "status" => action_draft.status
    }.merge(extra.compact.stringify_keys)
  end

  def dry_run?
    side_effect = action_draft.external_side_effect || {}
    side_effect["dry_run"] == true || side_effect["mode"].to_s == "demo"
  end

  def create_event(kind:, payload:, requires_review: false, source: "twilio_sms_executor", provider: TWILIO_PROVIDER)
    call_state.sidecar_events.create!(
      conversation: action_draft.conversation,
      source: source,
      kind: kind,
      provider: provider,
      payload: payload,
      evidence: { "action_draft_id" => action_draft.id },
      changes_call_behavior: false,
      requires_review: requires_review,
      occurred_at: Time.current
    )
  end

  def call_state
    action_draft.call_state
  end
end
