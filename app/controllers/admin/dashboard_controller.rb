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
      @readiness = IntegrationReadinessService.new.call
      @use_cases = UseCaseCatalog.all
    end
  end
end
