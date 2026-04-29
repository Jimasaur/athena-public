class ConversationDiscordNotificationService
  def initialize(conversation:)
    @conversation = conversation
  end

  def call
    return { ok: false, skipped: true, error: "Demo conversation notifications are skipped." } if demo_conversation?

    webhook_url = notification_webhook_url
    return { ok: false, skipped: true, error: "Discord webhook URL is missing." } if webhook_url.blank?

    DiscordWebhookService.new(
      url: webhook_url,
      username: notification_username
    ).post(
      content: content,
      embeds: [ embed ]
    )
  end

  private

  def notification_webhook_url
    AppSetting.fetch("DISCORD_CONVERSATIONS_WEBHOOK_URL").to_s.strip.presence ||
      AppSetting.fetch("ATHENA_CALLS_DISCORD_WEBHOOK_URL").to_s.strip.presence
  end

  def demo_conversation?
    @conversation.twilio_call_sid.to_s.start_with?("DEMO-") ||
      @conversation.customer&.metadata&.dig("demo") == true
  end

  def notification_username
    AppSetting.fetch("DISCORD_CONVERSATIONS_WEBHOOK_USERNAME").to_s.strip.presence ||
      AppSetting.fetch("ATHENA_CALLS_DISCORD_USERNAME").to_s.strip.presence ||
      "Athena"
  end

  def content
    channel_label = AppSetting.fetch("DISCORD_CONVERSATIONS_CHANNEL_LABEL").to_s.strip
    prefix = channel_label.present? ? "[#{channel_label}] " : ""
    "#{prefix}Conversation started: #{headline}"
  end

  def headline
    customer_name = @conversation.customer&.name.presence || "Unknown caller"
    summary = @conversation.summary.presence || "No summary yet"
    "#{customer_name} — #{summary.tr("\n", " ")[0, 140]}"
  end

  def embed
    {
      title: "Conversation Started",
      description: @conversation.summary.presence || "No summary available.",
      fields: [
        field("Customer", @conversation.customer&.name.presence || "Unknown"),
        field("Phone", @conversation.customer&.phone_number.presence || "Unknown"),
        field("Agent", @conversation.agent_name.presence || "Unknown"),
        field("Status", @conversation.status.to_s),
        field("Started", format_time(@conversation.call_started_at)),
        field("Conversation", admin_url.presence || "No admin URL configured")
      ],
      footer: {
        text: "Athena conversation reporting"
      }
    }
  end

  def field(name, value)
    {
      name: name,
      value: value.to_s.tr("\n", " ")[0, 1024].presence || "—",
      inline: false
    }
  end

  def format_time(value)
    return "Unknown" if value.blank?

    value.utc.iso8601
  end

  def admin_url
    base_url = AppSetting.fetch("PUBLIC_BASE_URL").to_s.strip
    return nil if base_url.blank?

    "#{base_url}/admin/conversations/#{@conversation.id}"
  end
end
