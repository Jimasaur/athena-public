module Admin
  class IdeaCapturesController < BaseController
    def index
      @idea_captures = IdeaCapture.includes(conversation: :customer).order(created_at: :desc)
      @idea_captures = @idea_captures.where(category: params[:category]) if params[:category].present?
      @idea_captures = @idea_captures.limit(100)
    end

    def show
      @idea_capture = IdeaCapture.includes(conversation: [ :customer, :messages, :sidecar_events ]).find(params[:id])
      @conversation = @idea_capture.conversation
    end
  end
end
