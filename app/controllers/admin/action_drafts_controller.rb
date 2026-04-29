module Admin
  class ActionDraftsController < BaseController
    before_action :load_action_draft

    def approve
      review_draft(:approve, notice: "Draft approved.")
    end

    def reject
      review_draft(:reject, notice: "Draft rejected.")
    end

    def execute
      result = ActionDraftExecutionService.new(
        action_draft: @action_draft,
        executor: params[:executor]
      ).call

      if result.ok
        redirect_to admin_conversation_path(@action_draft.conversation), notice: "Draft sent."
      else
        redirect_to admin_conversation_path(@action_draft.conversation), alert: result.error
      end
    end

    private

    def load_action_draft
      @action_draft = ActionDraft.includes(:conversation, :call_state).find(params[:id])
    end

    def review_draft(decision, notice:)
      ActionDraftReviewService.new(
        action_draft: @action_draft,
        decision: decision,
        reviewer: params[:reviewer],
        reason: params[:reason]
      ).call

      redirect_to admin_conversation_path(@action_draft.conversation), notice: notice
    rescue ActionDraftReviewService::AlreadyReviewed => error
      redirect_to admin_conversation_path(@action_draft.conversation), alert: error.message
    end
  end
end
