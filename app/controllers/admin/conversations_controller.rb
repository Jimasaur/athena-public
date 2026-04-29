module Admin
  class ConversationsController < BaseController
    def index
      @page = params[:page].to_i
      @page = 1 if @page < 1
      @per_page = 50
      @selected_agent = params[:agent_name].presence
      @selected_review = params[:review].presence
      @agent_options = Conversation.where.not(agent_name: [ nil, "" ]).distinct.order(:agent_name).pluck(:agent_name)

      scoped_conversations = Conversation.includes(:customer, :action_drafts, :call_state).order(created_at: :desc)
      if @selected_agent
        scoped_conversations = scoped_conversations.where(agent_name: @selected_agent)
      end
      @review_counts = review_counts_for(scoped_conversations)
      scoped_conversations = apply_review_filter(scoped_conversations, @selected_review)

      @total_count = scoped_conversations.count
      @total_pages = (@total_count.to_f / @per_page).ceil
      offset = (@page - 1) * @per_page

      @conversations = scoped_conversations
        .limit(@per_page)
        .offset(offset)
    end

    def show
      @conversation = Conversation.includes(:customer, :messages, :call_events, :call_state, :sidecar_events, :action_drafts).find(params[:id])
      @transcript_event = @conversation.transcript_call_event
      if @transcript_event.nil?
        @transcript_event = @conversation.call_events.order(created_at: :desc).find do |event|
          event.data.is_a?(Hash) && event.data["type"] == "post_call_transcription"
        end
      end
      @messages = @conversation.messages.order(:sent_at)
      @call_events = @conversation.call_events.order(created_at: :asc)
      @call_state = @conversation.call_state
      @sidecar_events = @conversation.sidecar_events.order(occurred_at: :asc, created_at: :asc)
      @action_drafts = @conversation.action_drafts.order(created_at: :desc)
      @timeline_entries = ConversationTimeline.new(@conversation).entries
      @review_state = ConversationReviewState.new(@conversation).to_h
    end

    def destroy
      conversation = Conversation.find(params[:id])
      conversation.destroy
      redirect_to admin_conversations_path, notice: "Conversation removed."
    end

    private

    def apply_review_filter(scope, selected_review)
      case selected_review
      when "needs_review"
        scope.joins(:action_drafts)
          .where(action_drafts: { status: ActionDraft::PENDING_APPROVAL_STATUS })
          .distinct
      when "ready_to_send"
        scope.joins(:action_drafts)
          .where(action_drafts: { status: ActionDraft::APPROVED_STATUS })
          .distinct
      when "executed"
        scope.joins(:action_drafts)
          .where(action_drafts: { status: ActionDraft::EXECUTED_STATUS })
          .distinct
      when "failed"
        scope.joins(:action_drafts)
          .where(action_drafts: { status: ActionDraft::EXECUTION_FAILED_STATUS })
          .distinct
      else
        scope
      end
    end

    def review_counts_for(scope)
      {
        "all" => scope.distinct.count,
        "needs_review" => count_with_draft_status(scope, ActionDraft::PENDING_APPROVAL_STATUS),
        "ready_to_send" => count_with_draft_status(scope, ActionDraft::APPROVED_STATUS),
        "executed" => count_with_draft_status(scope, ActionDraft::EXECUTED_STATUS),
        "failed" => count_with_draft_status(scope, ActionDraft::EXECUTION_FAILED_STATUS)
      }
    end

    def count_with_draft_status(scope, statuses)
      scope.joins(:action_drafts)
        .where(action_drafts: { status: statuses })
        .distinct
        .count
    end
  end
end
