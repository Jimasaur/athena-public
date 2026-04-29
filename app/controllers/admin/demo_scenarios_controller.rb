module Admin
  class DemoScenariosController < BaseController
    def index
      @scenarios = DemoScenarioCatalog.all
      @demo_conversations_by_slug = demo_conversations_by_slug(@scenarios)
      @latest_conversation = latest_conversation
      @latest_live_conversation = latest_live_conversation
      @live_demo = live_demo_status
    end

    def launch
      conversation = DemoScenarioSeedService.new(slug: params[:id]).call
      redirect_to admin_conversation_path(conversation), notice: "Demo scenario launched."
    rescue KeyError => error
      redirect_to admin_demo_scenarios_path, alert: error.message
    end

    def seed_all
      DemoScenarioCatalog.all.each do |scenario|
        DemoScenarioSeedService.new(slug: scenario[:slug]).call
      end

      redirect_to admin_demo_scenarios_path, notice: "All demo scenarios are ready."
    end

    private

    def demo_conversations_by_slug(scenarios)
      slugs = scenarios.map { |scenario| scenario[:slug] }
      CallState
        .includes(conversation: [ :customer, :action_drafts ])
        .where(use_case_slug: slugs)
        .where("call_id LIKE ?", "DEMO-%")
        .order(created_at: :desc)
        .each_with_object({}) do |call_state, records|
          records[call_state.use_case_slug] ||= call_state.conversation
        end
    end

    def latest_conversation
      Conversation.includes(:customer, :call_state, :action_drafts).order(created_at: :desc).first
    end

    def latest_live_conversation
      Conversation.includes(:customer, :call_state, :action_drafts)
        .where(status: "in_progress")
        .order(created_at: :desc)
        .first
    end

    def live_demo_status
      base_url = public_base_url
      {
        public_base_url: base_url,
        voice_webhook_url: "#{base_url}/voice/inbound",
        twilio_inbound_url: "#{base_url}#{twilio_inbound_path}",
        tool_command_url: "#{base_url}#{agent_tools_command_path}",
        stream_url: websocket_url(base_url, "/ws/twilio-media"),
        phone_numbers: phone_numbers,
        readiness: readiness_items,
        function_prompts: function_prompts
      }
    end

    def public_base_url
      AppSetting.fetch("PUBLIC_BASE_URL").to_s.strip.presence || request.base_url
    end

    def websocket_url(base_url, path)
      uri = URI(base_url)
      scheme = uri.scheme == "https" ? "wss" : "ws"
      "#{scheme}://#{uri.host}#{":#{uri.port}" if uri.port && ![ 80, 443 ].include?(uri.port)}#{path}"
    rescue URI::InvalidURIError
      path
    end

    def phone_numbers
      AgentSetting.where.not(twilio_number: [ nil, "" ]).order(:id).map do |setting|
        {
          name: setting.name.presence || setting.agent_id,
          agent_id: setting.agent_id,
          number: setting.twilio_number,
          first_message: setting.first_message,
          tools_count: Array(setting.tools).size
        }
      end
    end

    def readiness_items
      [
        readiness_item("Twilio voice credentials", AppSetting.fetch("TWILIO_ACCOUNT_SID").present? && AppSetting.fetch("TWILIO_AUTH_TOKEN").present?),
        readiness_item("Callable Twilio number", AgentSetting.where.not(twilio_number: [ nil, "" ]).exists?),
        readiness_item("OpenAI Realtime profile", AgentSetting.exists?),
        readiness_item("Public webhook URL", AppSetting.fetch("PUBLIC_BASE_URL").present?, AppSetting.fetch("PUBLIC_BASE_URL")),
        readiness_item("A2P campaign", AppSetting.fetch("TWILIO_A2P_CAMPAIGN_SID").present?, AppSetting.fetch("TWILIO_A2P_CAMPAIGN_SID").presence || "SMS can stay dry-run while vetting is pending"),
        readiness_item("OpenAI API key", ENV["OPENAI_API_KEY"].present? || AppSetting.fetch("OPENAI_API_KEY").present?),
        readiness_item("Local AI sidecar route", AppSetting.fetch("OPENCLAW_AGENT").present? || AppSetting.fetch("OPENCLAW_PROFILE").present?, [ AppSetting.fetch("OPENCLAW_AGENT"), AppSetting.fetch("OPENCLAW_PROFILE") ].compact_blank.join(" / "))
      ]
    end

    def readiness_item(label, ready, detail = nil)
      { label: label, ready: ready, detail: detail }
    end

    def function_prompts
      [
        {
          name: "Capture Idea",
          phrase: "Capture this as a rev cycle retreat idea.",
          endpoint: "agent_tools/capture_idea",
          value: "Creates a structured idea card and posts it to the Athena Discord channel when configured."
        },
        {
          name: "Status",
          phrase: "Run an Athena status check.",
          endpoint: "agent_tools/status",
          value: "Confirms app health, environment, and sidecar profile."
        },
        {
          name: "Latest Call",
          phrase: "Summarize my latest call.",
          endpoint: "agent_tools/summarize_last_call",
          value: "Pulls the most recent Athena conversation and transcript."
        },
        {
          name: "Contact Lookup",
          phrase: "Look up my contact record.",
          endpoint: "agent_tools/lookup",
          value: "Uses the caller phone number to return a compact customer profile."
        },
        {
          name: "Web Search",
          phrase: "Search the web for the latest OpenAI Realtime notes and summarize.",
          endpoint: "agent_tools/web_search",
          value: "Routes current-info questions through the configured research sidecar."
        },
        {
          name: "OpenClaw",
          phrase: "Ask OpenClaw for three demo improvements.",
          endpoint: "agent_tools/openclaw_chat",
          value: "Hands deeper reasoning to a local AI sidecar and returns a voice-sized answer."
        },
        {
          name: "Draft Follow-Up",
          phrase: "Draft a follow-up text, but do not send it.",
          endpoint: "agent_tools/draft_follow_up",
          value: "Creates an approval-gated action draft in the Athena review queue."
        },
        {
          name: "Gemma Mail",
          phrase: "Draft an email through Gemma Mail, but keep it for review.",
          endpoint: "agent_tools/gmail_send",
          value: "Uses a Gmail connector when configured, otherwise falls back to the gemma-mail OpenClaw agent."
        }
      ]
    end
  end
end
