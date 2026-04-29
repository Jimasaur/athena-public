module Admin
  class DashboardController < BaseController
    def show
      @demo_conversation = Conversation
        .left_joins(:call_state)
        .includes(:customer)
        .where(call_states: { provider: "openai_realtime" })
        .order(created_at: :desc)
        .first
      @latest_conversations = Conversation.includes(:customer).order(created_at: :desc).limit(5)
      @latest_ideas = IdeaCapture.includes(conversation: :customer).order(created_at: :desc).limit(5)
      @pending_drafts = ActionDraft.includes(conversation: :customer)
        .where(status: ActionDraft::PENDING_APPROVAL_STATUS)
        .order(created_at: :desc)
        .limit(5)
      @executed_actions = ActionDraft.includes(conversation: :customer)
        .where(status: ActionDraft::EXECUTED_STATUS)
        .order(updated_at: :desc)
        .limit(5)
      @readiness = readiness_items
      @use_cases = UseCaseCatalog.all
    end

    private

    def readiness_items
      [
        readiness_item("Twilio credentials", AppSetting.fetch("TWILIO_ACCOUNT_SID").present? && AppSetting.fetch("TWILIO_AUTH_TOKEN").present?),
        readiness_item("A2P Messaging Service", AppSetting.fetch("TWILIO_MESSAGING_SERVICE_SID").present?, AppSetting.fetch("TWILIO_MESSAGING_SERVICE_SID")),
        readiness_item("A2P Campaign", AppSetting.fetch("TWILIO_A2P_CAMPAIGN_SID").present?, AppSetting.fetch("TWILIO_A2P_CAMPAIGN_SID")),
        readiness_item("OpenAI Realtime", AppSetting.fetch("OPENAI_API_KEY").present? && AppSetting.fetch("OPENAI_REALTIME_MODEL").present?, AppSetting.fetch("OPENAI_REALTIME_MODEL")),
        readiness_item("Realtime agent profile", AgentSetting.exists?),
        readiness_item("Athena idea Discord", AppSetting.fetch("ATHENA_IDEAS_DISCORD_WEBHOOK_URL").present? || AppSetting.fetch("ATHENA_IDEAS_DISCORD_TARGET").present?, AppSetting.fetch("ATHENA_IDEAS_DISCORD_TARGET").presence),
        readiness_item("Admin auth", AppSetting.fetch("ADMIN_USERNAME").present? && AppSetting.fetch("ADMIN_PASSWORD").present?),
        readiness_item("Twilio signatures", ActiveModel::Type::Boolean.new.cast(AppSetting.fetch("TWILIO_VERIFY_WEBHOOK_SIGNATURES")))
      ]
    end

    def readiness_item(label, ready, detail = nil)
      {
        label: label,
        ready: ready,
        detail: detail
      }
    end
  end
end
