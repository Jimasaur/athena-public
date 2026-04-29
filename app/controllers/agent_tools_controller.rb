class AgentToolsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_tool_secret!

  def lookup
    phone_number = params[:phone_number] || params[:phone]
    customer = CustomerLookupService.new(phone_number: phone_number).call

    if customer
      render json: {
        found: true,
        customer: customer_payload(customer)
      }
    else
      render json: { found: false, customer: nil }, status: :not_found
    end
  end

  def update
    customer = find_customer
    return render json: { updated: false, error: "Patient not found" }, status: :not_found unless customer

    attributes = {
      name: params[:name],
      metadata: params[:metadata]
    }

    updated = CustomerUpdateService.new(customer: customer, attributes: attributes).call

    if updated
      render json: { updated: true, customer: customer_payload(customer.reload) }
    else
      render json: { updated: false, errors: customer.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def web_search
    result = web_search_result

    if result[:ok]
      render json: result
    else
      render json: result, status: result[:status] || :unprocessable_entity
    end
  end

  def openclaw_chat
    prompt = params[:prompt] || params[:message]
    result = OpenClawAgentService.new(
      prompt: prompt,
      agent: params[:agent],
      thinking: params[:thinking],
      session_id: params[:session_id],
      profile: params[:profile]
    ).call

    if result[:ok]
      render json: result
    else
      render json: result, status: result[:status] || :unprocessable_entity
    end
  end

  def status
    render json: status_payload
  end

  def command
    command_name = params[:command].to_s.strip
    return render json: { ok: false, error: "Command is required" }, status: :unprocessable_entity if command_name.blank?

    case command_name
    when "status"
      render json: status_payload
    when "semantic_request"
      semantic_request
    when "summarize_last_call"
      summarize_last_call
    when "find_contact"
      find_contact
    when "capture_idea"
      capture_idea
    when "draft_follow_up"
      draft_follow_up
    when "gmail_send", "email", "email_draft"
      gmail_send
    when "web_search"
      web_search
    when "openclaw_chat"
      openclaw_chat
    when "lookup"
      lookup
    when "update"
      update
    else
      render json: { ok: false, error: "Unknown command: #{command_name}" }, status: :not_found
    end
  end

  def semantic_request
    request_text = params[:request].to_s.strip
    return render json: { ok: false, error: "Request is required" }, status: :unprocessable_entity if request_text.blank?

    result = route_semantic_request(request_text)
    render json: result[:body], status: result[:status]
  end

  def summarize_last_call
    result = summarize_last_call_result
    return render json: result, status: :not_found unless result[:ok]

    render json: result
  end

  def find_contact
    find_contact_response = find_contact_response_for(params[:query].to_s.strip)
    render json: find_contact_response[:body], status: find_contact_response[:status]
  end

  def capture_idea
    result = capture_idea_result
    render json: result, status: result[:ok] ? :ok : (result[:status] || :unprocessable_entity)
  end

  def draft_follow_up
    result = draft_follow_up_result

    if result[:ok]
      render json: result.merge(command: "draft_follow_up")
    else
      render json: result, status: result[:status] || :unprocessable_entity
    end
  end

  def athena_calls_latest
    limit = params[:limit] || params[:max_results]
    scope = Conversation.includes(:customer).order(created_at: :desc)
    scope = scope.where(channel: params[:channel]) if params[:channel].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    if params[:phone_number].present? || params[:phone].present?
      phone_number = params[:phone_number] || params[:phone]
      scope = scope.joins(:customer).where(customers: { phone_number: phone_number })
    end

    records = scope.limit(normalize_limit(limit))
    render json: {
      ok: true,
      calls: records.map { |conversation| conversation_payload(conversation) }
    }
  end

  def athena_call_summary
    conversation = find_conversation
    return render json: { ok: false, error: "Call not found" }, status: :not_found unless conversation

    render json: {
      ok: true,
      call: conversation_payload(conversation).merge(
        transcript: transcript_payload(conversation),
        recent_messages: conversation.messages.order(:sent_at, :created_at).last(8).map do |message|
          {
            role: message.role,
            content: message.content,
            sent_at: message.sent_at
          }
        end
      )
    }
  end

  def calendar_availability
    result = ConfiguredJsonWebhookToolService.new(
      setting_key: "GOOGLE_CALENDAR_TOOL_URL",
      payload: params.to_unsafe_h.except("controller", "action")
    ).call

    if result[:ok]
      render json: result
    else
      render json: result, status: result[:status] || :unprocessable_entity
    end
  end

  def gmail_send
    result = gmail_send_result

    if result[:ok]
      render json: result.merge(command: "gmail_send")
    else
      render json: result, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def find_customer
    if params[:customer_id].present?
      Customer.find_by(id: params[:customer_id])
    else
      phone_number = params[:phone_number] || params[:phone]
      Customer.find_by(phone_number: phone_number)
    end
  end

  def customer_payload(customer)
    {
      id: customer.id,
      name: customer.name,
      phone_number: customer.phone_number,
      metadata: customer.metadata
    }
  end

  def find_conversation
    return Conversation.includes(:customer, :messages).find_by(id: params[:conversation_id]) if params[:conversation_id].present?
    return Conversation.includes(:customer, :messages).find_by(twilio_call_sid: params[:call_sid]) if params[:call_sid].present?

    nil
  end

  def conversation_payload(conversation)
    {
      id: conversation.id,
      customer: customer_payload(conversation.customer),
      channel: conversation.channel,
      status: conversation.status,
      summary: conversation.summary,
      agent_name: conversation.agent_name,
      twilio_call_sid: conversation.twilio_call_sid,
      call_started_at: conversation.call_started_at,
      created_at: conversation.created_at,
      updated_at: conversation.updated_at
    }
  end

  def transcript_payload(conversation)
    transcript_event = conversation.transcript_call_event
    return nil unless transcript_event

    {
      status: transcript_event.status,
      transcription: transcript_event.transcription,
      data: transcript_event.data
    }
  end

  def normalize_limit(value)
    parsed = value.to_i
    return 5 if parsed <= 0

    [ parsed, 10 ].min
  end

  def status_payload
    {
      ok: true,
      command: "status",
      app: {
        name: "Athena",
        time_utc: Time.current.utc.iso8601,
        rails_env: Rails.env,
        openclaw_profile: AppSetting.fetch("OPENCLAW_PROFILE").presence,
        openclaw_agent: AppSetting.fetch("OPENCLAW_AGENT").presence
      }
    }
  end

  def route_semantic_request(request_text)
    intent = classify_semantic_request(request_text)

    case intent
    when :status
      { status: :ok, body: status_payload }
    when :weather
      location = extract_location_from_weather_request(request_text)
      if location.blank?
        { status: :ok, body: { ok: false, command: "semantic_request", error: "I need your location to check the weather." } }
      else
        result = web_search_result_for(query: weather_search_query(location), max_results: 3)
        body = result.merge(
          command: "semantic_request",
          intent: "weather",
          location: location,
          reply: weather_search_reply(location, result)
        )
        { status: result[:ok] ? :ok : (result[:status] || :unprocessable_entity), body: body }
      end
    when :summarize_last_call
      result = summarize_last_call_result
      { status: result[:ok] ? :ok : :not_found, body: result }
    when :find_contact
      result = find_contact_response_for(request_text)
      { status: result[:status], body: result[:body] }
    when :capture_idea
      result = capture_idea_result("request" => request_text)
      { status: result[:ok] ? :ok : (result[:status] || :unprocessable_entity), body: result }
    when :web_search
      result = web_search_result_for(query: request_text)
      body = result.merge(
        command: "semantic_request",
        intent: "web_search",
        reply: web_search_reply(request_text, result)
      )
      { status: result[:ok] ? :ok : (result[:status] || :unprocessable_entity), body: body }
    when :email
      result = if (draft_id = extract_draft_id(request_text))
        email_draft_status_result(draft_id)
      else
        gemma_mail_approval_handoff_result("request" => request_text)
      end
      result[:ok] ? { status: :ok, body: result.merge(command: "gmail_send") } : { status: result[:status] || :unprocessable_entity, body: result.merge(command: "gmail_send") }
    else
      result = OpenClawAgentService.new(
        prompt: semantic_request_prompt(request_text),
        agent: params[:agent],
        thinking: params[:thinking],
        session_id: params[:session_id],
        profile: params[:profile]
      ).call
      result[:ok] ? { status: :ok, body: result.merge(command: "semantic_request") } : { status: result[:status] || :unprocessable_entity, body: result.merge(command: "semantic_request") }
    end
  end

  def classify_semantic_request(request_text)
    text = request_text.to_s.downcase.strip
    return :status if text.match?(/\b(status|health|healthy|up|running)\b/)
    return :weather if text.match?(/\b(weather|forecast|temperature|rain|snow|wind)\b/)
    return :summarize_last_call if text.match?(/\b(summarize|summary|recap|last call|latest call)\b/)
    return :find_contact if text.match?(/\b(find|lookup|who is|who\s+is|contact)\b/)
    return :capture_idea if text.match?(/\b(idea|automation|innovation|cost savings|rev cycle|revenue cycle|improvement|retreat)\b/)
    return :email if text.match?(/\b(email|gmail|mail|inbox)\b/)
    return :draft_follow_up if text.match?(/\b(draft|follow[- ]?up|followup|message|note)\b/)
    return :web_search if text.match?(/\b(search the web|web search|news|current|latest)\b/)

    :openclaw
  end

  def extract_location_from_weather_request(request_text)
    request_text.to_s
      .sub(/\A.*?\b(?:weather|forecast|temperature|rain|snow|wind)\b(?:\s+(?:in|for|at|near))?\s*/i, "")
      .gsub(/\b(?:today|tomorrow|right now|currently|now|please)\b/i, "")
      .gsub(/\s+/, " ")
      .gsub(/\A(?:in|for|at|near)\s+/i, "")
      .gsub(/[?.!,]+\z/, "")
      .strip
      .presence
  end

  def weather_search_query(location)
    "current weather #{location}"
  end

  def weather_search_reply(location, result)
    return "I could not fetch weather for #{location}: #{result[:error]}" unless result[:ok]

    summary = search_results_summary(result)
    if summary.blank?
      return "I searched for current weather in #{location}, but did not find a usable weather result."
    end

    "I searched Brave Search for current weather in #{location}. Top snippets: #{summary}".truncate(650)
  end

  def web_search_reply(query, result)
    return "I could not complete the web search: #{result[:error]}" unless result[:ok]

    summary = search_results_summary(result)
    return "I searched for #{query}, but did not find usable results." if summary.blank?

    "Top web results for #{query}: #{summary}".truncate(650)
  end

  def search_results_summary(result)
    Array(result[:results] || result["results"]).first(3).filter_map do |item|
      title = clean_search_text(item[:title] || item["title"])
      description = clean_search_text(item[:description] || item["description"])
      next if title.blank? && description.blank?

      [ title, description ].compact_blank.join(": ")
    end.join(" ")
  end

  def clean_search_text(text)
    helpers.strip_tags(text.to_s).squish
  end

  def find_contact_response_for(query)
    return { status: :unprocessable_entity, body: { ok: false, error: "Query is required" } } if query.blank?

    scope = Customer.all
    digits = query.gsub(/\D/, "")
    scope = scope.where(phone_number: [ query, digits, "+#{digits}" ].compact.uniq) if digits.present?
    scope = scope.where("LOWER(name) LIKE ?", "%#{query.downcase}%") if query.match?(/[[:alpha:]]/)

    contacts = scope.order(created_at: :desc).limit(5)
    {
      status: :ok,
      body: {
        ok: true,
        command: "find_contact",
        query: query,
        found: contacts.any?,
        contacts: contacts.map { |customer| customer_payload(customer) }
      }
    }
  end

  def capture_idea_result(extra_payload = {})
    conversation = find_conversation ||
      Conversation.includes(:customer, :messages).order(created_at: :desc).first
    return { ok: false, command: "capture_idea", error: "Conversation is required.", status: 422 } unless conversation

    AthenaIdeaCaptureService.new(
      conversation: conversation,
      payload: params.to_unsafe_h.except("controller", "action").merge(extra_payload)
    ).call
  end

  def web_search_result
    query = params[:query].presence || params[:q].presence || params[:request].presence
    web_search_result_for(query: query, max_results: params[:max_results] || params[:limit])
  end

  def web_search_result_for(query:, max_results: nil)
    WebSearchService.new(query: query, max_results: max_results).call
  end

  def draft_follow_up_result
    OpenClawAgentService.new(
      prompt: draft_follow_up_prompt,
      agent: params[:agent],
      thinking: params[:thinking],
      session_id: params[:session_id],
      profile: params[:profile]
    ).call
  end

  def gmail_send_result(extra_payload = {})
    payload = params.to_unsafe_h.except("controller", "action").merge(extra_payload)
    return gemma_mail_approval_handoff_result(payload) if approval_handoff_requested?(payload)

    if AppSetting.fetch("GMAIL_TOOL_URL").to_s.strip.present?
      return ConfiguredJsonWebhookToolService.new(
        setting_key: "GMAIL_TOOL_URL",
        payload: payload
      ).call
    end

    GemmaMailAgentService.new(
      payload: payload,
      agent: params[:agent],
      thinking: params[:thinking],
      session_id: params[:session_id],
      profile: params[:profile]
    ).call
  end

  def gemma_mail_approval_handoff_result(extra_payload = {})
    payload = params.to_unsafe_h.except("controller", "action").merge(extra_payload)
    conversation = find_conversation ||
      Conversation.includes(:customer, :messages).order(created_at: :desc).first

    GemmaMailApprovalHandoffService.new(
      conversation: conversation,
      payload: payload
    ).call
  end

  def summarize_last_call_result
    conversation = find_conversation ||
      Conversation.includes(:customer, :messages, :call_events).order(created_at: :desc).first
    return { ok: false, command: "summarize_last_call", error: "No calls found" } unless conversation

    recent_messages = conversation.messages.order(:sent_at, :created_at).last(8).map do |message|
      {
        role: message.role,
        content: message.content,
        sent_at: message.sent_at
      }
    end

    {
      ok: true,
      command: "summarize_last_call",
      reply: voice_summary_for(conversation, recent_messages),
      call: conversation_payload(conversation).merge(
        transcript: transcript_payload(conversation),
        recent_messages: recent_messages
      )
    }
  end

  def voice_summary_for(conversation, recent_messages)
    user_messages = recent_messages.select { |message| message[:role] == "user" }.map { |message| message[:content].to_s.squish }
    assistant_messages = recent_messages.select { |message| message[:role] == "assistant" }.map { |message| message[:content].to_s.squish }
    latest_user = user_messages.last.presence || "No user request was captured yet."
    latest_assistant = assistant_messages.last.presence || "No assistant response was captured yet."
    caller = conversation.customer&.name.presence || "the caller"

    "Latest call with #{caller} is #{conversation.status.humanize.downcase}. Most recent user request: #{latest_user}. Latest assistant response: #{latest_assistant}."
  end

  def local_email_draft_result(extra_payload = {})
    payload = params.to_unsafe_h.except("controller", "action").merge(extra_payload).with_indifferent_access
    request_text = payload[:request].to_s.strip
    to = payload[:to].presence || extract_email(request_text)
    subject = payload[:subject].presence || extract_labeled_value(request_text, "subject") || "Follow-up"
    body = payload[:body].presence || payload[:text].presence || extract_labeled_value(request_text, "body") || request_text.presence

    return { ok: false, error: "Email recipient is required.", status: 422 } if to.blank?
    return { ok: false, error: "Email body is required.", status: 422 } if body.blank?

    conversation = find_conversation ||
      Conversation.includes(:customer, :messages).order(created_at: :desc).first
    return { ok: false, error: "Conversation is required to create an email draft.", status: 422 } unless conversation

    call_state = CallState.ensure_for_conversation(
      conversation,
      provider: conversation.call_state&.provider.presence || "openai_realtime",
      call_id: conversation.twilio_call_sid || "conversation-#{conversation.id}",
      status: conversation.status == "completed" ? "completed" : "active"
    )
    draft = call_state.action_drafts.create!(
      conversation: conversation,
      kind: "email",
      created_by: "agent_tool",
      approval_required: true,
      recipient: { email: to },
      content: {
        subject: subject,
        body: body,
        request: request_text.presence
      }.compact,
      external_side_effect: {
        type: "send_email",
        provider: "local_email_draft",
        requested_mode: requested_email_mode(payload),
        executed: false
      }
    )

    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "agent_tool",
      kind: "action_draft.created",
      provider: "athena",
      payload: {
        action_draft_id: draft.id,
        action_kind: draft.kind,
        status: draft.status,
        recipient: draft.recipient,
        subject: subject
      },
      evidence: { action_draft_id: draft.id },
      changes_call_behavior: false,
      requires_review: true,
      occurred_at: Time.current
    )

    {
      ok: true,
      provider: "athena",
      action: "gmail_draft",
      mode: "draft",
      draft_id: draft.id,
      reply: "I created an email draft for review. It has not been sent yet."
    }
  end

  def requested_email_mode(payload)
    raw = (payload[:mode].presence || payload[:action].presence).to_s.downcase
    return "send" if truthy?(payload[:send]) || raw.in?([ "send", "deliver", "sent" ])

    "draft"
  end

  def approval_handoff_requested?(payload)
    payload = payload.to_h.with_indifferent_access
    raw = (payload[:mode].presence || payload[:action].presence).to_s.downcase
    return true if truthy?(payload[:approval]) || truthy?(payload[:approval_workflow]) || raw.in?([ "approval", "approve", "review" ])
    return false if truthy?(payload[:send]) || raw.in?([ "send", "deliver", "sent", "draft" ])

    true
  end

  def email_draft_status_result(draft_id)
    draft = ActionDraft.find_by(id: draft_id, kind: "email")
    return { ok: false, error: "Email draft #{draft_id} was not found.", status: 404 } unless draft

    reply =
      if draft.status == ActionDraft::EXECUTED_STATUS
        "Email draft #{draft.id} has already been sent."
      elsif draft.executable?
        "Email draft #{draft.id} is approved in Athena and ready for an admin to send. It has not been sent yet."
      elsif draft.pending_approval?
        "Email draft #{draft.id} is waiting for review in Athena. It has not been sent yet."
      else
        "Email draft #{draft.id} is #{draft.status.humanize.downcase}. It has not been sent."
      end

    {
      ok: true,
      provider: "athena",
      action: "gmail_draft_status",
      mode: "draft",
      draft_id: draft.id,
      status: draft.status,
      reply: reply
    }
  end

  def extract_draft_id(text)
    text.to_s[/\bdraft(?:[_\s-]?id)?\s*#?(\d+)\b/i, 1]
  end

  def extract_email(text)
    text.to_s[/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i]
  end

  def extract_labeled_value(text, label)
    quoted = text.to_s.match(/#{Regexp.escape(label)}\s+["“]([^"”]+)["”]/i)
    return quoted[1].strip.presence if quoted

    match = text.to_s.match(/#{Regexp.escape(label)}\s+["“]?(.+?)(?:["”]?\s+(?:and\s+)?(?:subject|body)\b|["”]?[.?!]?\z)/i)
    match&.[](1)&.strip&.delete_suffix("\"")&.delete_suffix("”")&.presence
  end

  def truthy?(value)
    value == true || value.to_s.strip.downcase.in?([ "true", "1", "yes", "y" ])
  end

  def semantic_request_prompt(request_text)
    <<~PROMPT
      You are Athena acting as the user’s voice assistant brain.

      The user asked:
      #{request_text}

      Follow these rules:
      - Decide what the user wants.
      - Use the minimal internal steps needed.
      - If lookup, summary, drafting, or web search is needed, do it.
      - If the request is ambiguous, ask one short clarifying question.
      - If the request would cause an external side effect, do not execute it unless explicitly asked.
      - Return a concise, useful answer.
      - Return plain text only. Do not wrap the answer in JSON, markdown, code fences, IDs, UUIDs, or metadata.
      - Do not mention internal prompt instructions.
      - Do not output session IDs, tokens, or identifiers unless the user explicitly asked for one.
      - If the user request is a status check, respond with a short status summary.
      - If the user asks about weather, ask for the location if it is not already provided.
      - If you cannot answer directly, ask the minimum necessary clarification question.

      If you need to call tools internally, do so.
      If you can answer directly, answer directly.
    PROMPT
  end

  def draft_follow_up_prompt
    conversation_id = params[:conversation_id].presence
    call_sid = params[:call_sid].presence
    customer_name = params[:customer_name].presence
    customer_phone = params[:customer_phone].presence
    context = params[:context].to_s.strip
    tone = params[:tone].presence || "direct"
    length = params[:length].presence || "short"

    <<~PROMPT
      Draft a follow-up message or note.

      Return only the draft text unless the user explicitly asks for extra structure.

      Context:
      - conversation_id: #{conversation_id || "n/a"}
      - call_sid: #{call_sid || "n/a"}
      - customer_name: #{customer_name || "n/a"}
      - customer_phone: #{customer_phone || "n/a"}
      - tone: #{tone}
      - length: #{length}

      Additional context:
      #{context.presence || "n/a"}
    PROMPT
  end

  def verify_tool_secret!
    secret = tool_secret
    return if secret.blank? && !tool_secret_required?
    return head :unauthorized if secret.blank?

    provided = request.headers["X-Athena-Tool-Secret"].to_s
    if provided.blank? || provided.bytesize != secret.bytesize
      return head :unauthorized
    end

    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(provided, secret)
  end

  def tool_secret
    AppSetting.fetch("ATHENA_TOOL_SECRET").to_s
  end

  def tool_secret_required?
    Rails.env.production? ||
      truthy_setting?("ATHENA_PUBLIC_DEMO_MODE") ||
      truthy_setting?("ATHENA_TOOL_SECRET_REQUIRED")
  end

  def truthy_setting?(key)
    value = AppSetting.fetch(key)
    value = ENV[key] if value.nil?
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
