require "ipaddr"
require "uri"

# A local configuration inventory, never a provider health check. Do not return
# credential values: these rows are displayed together in the admin interface.
class IntegrationReadinessService
  PLACEHOLDER_PATTERN = /your[_ -]|change[-_ ]?(?:this|me)|example|replace[-_ ]?(?:me|this)|<[^>]+>/i
  SAMPLE_PHONE_NUMBERS = %w[+15551234567 +14155551234].freeze

  def initialize(settings: AppSetting, agents: AgentSetting.all, environment: Rails.env)
    @settings = settings
    @agents = agents
    @environment = environment.to_s
    @values = {}
  end

  def call
    {
      local_demo: item("Local synthetic demo", :configured,
        "Seeded scenarios use simulated conversations and actions. No provider credentials are needed to explore them."),
      integrations: [
        configuration("Twilio voice credentials", %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN]),
        openai_configuration,
        agent_configuration,
        phone_configuration,
        public_url_configuration,
        configuration("A2P Messaging Service", %w[TWILIO_MESSAGING_SERVICE_SID],
          detail: "Messaging Service ID present; registration, consent, and delivery have not been verified."),
        configuration("A2P campaign", %w[TWILIO_A2P_CAMPAIGN_SID],
          detail: "Campaign ID present; approval and sending eligibility have not been verified."),
        discord_configuration,
        sidecar_configuration
      ],
      security: [ admin_configuration, tool_configuration, context_configuration, signature_configuration ]
    }
  end

  private

  def value(key)
    @values.fetch(key) { @values[key] = @settings.fetch(key, nil).to_s.strip }
  end

  def placeholder?(value)
    value.match?(PLACEHOLDER_PATTERN)
  end

  def truthy?(key)
    ActiveModel::Type::Boolean.new.cast(value(key))
  end

  def item(label, status, detail)
    { label: label, status: status, detail: detail }
  end

  def configuration(label, keys, detail: "Settings are present; provider access and delivery have not been tested.")
    placeholders = keys.select { |key| placeholder?(value(key)) }
    missing = keys.select { |key| value(key).empty? }
    if placeholders.any?
      item(label, :needs_review, "Replace placeholder values for #{placeholders.join(', ')}.")
    elsif missing.any?
      item(label, :missing, "Add #{missing.join(', ')} to configure this integration.")
    else
      item(label, :configured, detail)
    end
  end

  def openai_configuration
    keys = %w[OPENAI_API_KEY]
    keys << "OPENAI_REALTIME_MODEL" if value("OPENAI_REALTIME_MODEL").present?
    configuration("OpenAI Realtime", keys,
      detail: "API key present; the configured model or application default is used. Model access and live audio have not been tested.")
  end

  def agent_configuration
    if @agents.any?
      item("Realtime agent profile", :configured, "An agent profile exists. Review its prompt, tools, and phone mapping before a live call.")
    else
      item("Realtime agent profile", :missing, "Create an agent profile under Agents before routing a live call.")
    end
  end

  def phone_configuration
    numbers = @agents.map { |agent| agent.twilio_number.to_s.strip }.reject(&:empty?)
    if numbers.empty?
      item("Twilio number mapping", :missing, "Map a Twilio number to an agent under Agents.")
    elsif numbers.any? { |number| number.match?(/\A\+[1-9]\d{6,14}\z/) && !SAMPLE_PHONE_NUMBERS.include?(number) }
      item("Twilio number mapping", :configured, "A phone mapping is present. Number ownership, voice capability, and inbound routing have not been tested.")
    else
      item("Twilio number mapping", :needs_review, "Replace sample numbers and use an E.164 number owned by your Twilio account.")
    end
  end

  def public_url_configuration
    result = configuration("Public webhook URL", %w[PUBLIC_BASE_URL],
      detail: "An HTTPS origin is configured. Public reachability, TLS, and Twilio routing have not been tested.")
    return result unless result[:status] == :configured

    uri = URI.parse(value("PUBLIC_BASE_URL"))
    valid = uri.is_a?(URI::HTTPS) && uri.host.present? && public_host?(uri.host) &&
      uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && [ "", "/" ].include?(uri.path)
    return result if valid

    item("Public webhook URL", :needs_review, "Set PUBLIC_BASE_URL to a public HTTPS origin without credentials, a path, query, or fragment.")
  rescue URI::InvalidURIError
    item("Public webhook URL", :needs_review, "PUBLIC_BASE_URL is not a valid HTTPS origin.")
  end

  def public_host?(host)
    normalized = host.downcase.delete_prefix("[").delete_suffix("]")
    return false if normalized == "localhost" || normalized.end_with?(".localhost", ".local", ".internal", ".test", ".invalid", ".example")

    address = IPAddr.new(normalized)
    OutboundUrlPolicy::BLOCKED_RANGES.none? { |range| range.include?(address) }
  rescue IPAddr::InvalidAddressError
    normalized.include?(".")
  end

  def discord_configuration
    if value("ATHENA_IDEAS_DISCORD_WEBHOOK_URL").present?
      result = configuration("Athena idea Discord", %w[ATHENA_IDEAS_DISCORD_WEBHOOK_URL])
      return result unless result[:status] == :configured

      uri = URI.parse(value("ATHENA_IDEAS_DISCORD_WEBHOOK_URL"))
      valid = uri.is_a?(URI::HTTPS) && OutboundUrlPolicy::DISCORD_WEBHOOK_HOSTS.include?(uri.host.to_s.downcase) &&
        uri.path.match?(OutboundUrlPolicy::DISCORD_WEBHOOK_PATH) && uri.userinfo.nil? && uri.fragment.nil?
      return result if valid

      item("Athena idea Discord", :needs_review, "Use an HTTPS Discord webhook URL. Delivery has not been tested.")
    else
      configuration("Athena idea Discord", %w[ATHENA_IDEAS_DISCORD_TARGET],
        detail: "An OpenClaw Discord target is configured. CLI installation, channel permissions, and delivery have not been tested.")
    end
  rescue URI::InvalidURIError
    item("Athena idea Discord", :needs_review, "Review the Discord webhook URL; it is not a valid HTTPS URL.")
  end

  def sidecar_configuration
    keys = %w[OPENCLAW_AGENT OPENCLAW_PROFILE].select { |key| value(key).present? }
    return item("Local AI sidecar route", :missing, "Optional: set OPENCLAW_AGENT or OPENCLAW_PROFILE to select a sidecar route.") if keys.empty?

    configuration("Local AI sidecar route", keys,
      detail: "Route settings are present. The local CLI, authentication, and agent execution have not been tested.")
  end

  def admin_configuration
    if truthy?("ATHENA_PUBLIC_DEMO_MODE") && value("ATHENA_PROXY_AUTH_SECRET").present?
      configuration("Admin authentication", %w[ATHENA_PROXY_AUTH_SECRET],
        detail: "Proxy authentication is configured. Restrict direct origin access and review proxy header handling before sharing.")
    else
      configuration("Admin authentication", %w[ADMIN_USERNAME ADMIN_PASSWORD],
        detail: "Admin credentials are present. Review credential strength and the deployed access boundary before sharing.")
    end
  end

  def tool_configuration
    configuration("Tool authentication", %w[ATHENA_TOOL_SECRET],
      detail: "A shared tool secret is present. Review its strength, storage, and authorized callers before sharing.")
  end

  def context_configuration
    required = @environment == "production" || truthy?("ATHENA_PUBLIC_DEMO_MODE") ||
      truthy?("ATHENA_AGENT_TOOLS_REQUIRE_CONTEXT") || (@environment != "test" && value("PUBLIC_BASE_URL").present?)
    if required
      item("Call-scoped tools", :configured, "Verified call context is required for call-scoped commands. Review other tool permissions separately.")
    else
      item("Call-scoped tools", :needs_review, "Local legacy access is enabled. Set ATHENA_AGENT_TOOLS_REQUIRE_CONTEXT=true before sharing.")
    end
  end

  def signature_configuration
    if truthy?("TWILIO_VERIFY_WEBHOOK_SIGNATURES")
      item("Twilio signatures", :configured, "Signature verification is enabled. Test with the deployed public URL and real Twilio callbacks.")
    else
      item("Twilio signatures", :needs_review, "Set TWILIO_VERIFY_WEBHOOK_SIGNATURES=true before accepting public Twilio callbacks.")
    end
  end
end
