module Admin
  class IdeaCapturesController < BaseController
    PAGE_SIZE = 25

    def index
      @query = params[:q].to_s.strip.first(200)
      @category = params[:category].to_s.strip
      @status = params[:status].to_s.strip
      @filters = { q: @query, category: @category, status: @status }.reject { |_key, value| value.blank? }
      ideas = IdeaCapture.search(@query)
      ideas = ideas.where(category: @category) if @category.present?
      ideas = ideas.where(status: @status) if @status.present?

      respond_to do |format|
        format.html do
          @categories = IdeaCapture.where.not(category: [ nil, "" ]).distinct.order(:category).pluck(:category)
          @total_count = IdeaCapture.count
          @filtered_count = ideas.count
          @total_pages = [ (@filtered_count + PAGE_SIZE - 1) / PAGE_SIZE, 1 ].max
          @page = params[:page].to_s.to_i.clamp(1, @total_pages)
          @idea_captures = ideas.includes(conversation: :customer).newest_first.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
          @first_result = @filtered_count.zero? ? 0 : (@page - 1) * PAGE_SIZE + 1
          @last_result = [ @page * PAGE_SIZE, @filtered_count ].min
        end
        format.csv do
          response.headers["Content-Type"] = "text/csv; charset=utf-8"
          response.headers["Content-Disposition"] = "attachment; filename=\"athena-ideas-#{Date.current.iso8601}.csv\""
          response.headers["Cache-Control"] = "no-store"
          self.response_body = ideas.each_csv_row
        end
      end
    end

    def show
      @idea_capture = IdeaCapture.includes(conversation: [ :customer, :messages, :sidecar_events ]).find(params[:id])
      @conversation = @idea_capture.conversation
    end

    def review
      change_review_status("reviewed", "Idea marked as reviewed.")
    end

    def archive
      change_review_status("archived", "Idea archived.")
    end

    def reopen
      change_review_status("captured", "Idea returned to the review queue.")
    end

    private

    def change_review_status(status, notice)
      idea = IdeaCapture.find(params[:id])
      idea.transition_review_status!(status)
      redirect_to admin_idea_capture_path(idea), notice: notice
    end
  end
end
