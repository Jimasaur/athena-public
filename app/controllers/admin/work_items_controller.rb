module Admin
  class WorkItemsController < BaseController
    PAGE_SIZE = 25
    EVENT_LIMIT = 100

    before_action :load_work_item, only: [ :show, :edit, :update ]

    def index
      @query = params[:q].to_s.strip.first(200)
      @view = %w[open needs_review unassigned overdue all].include?(params[:view]) ? params[:view] : "open"
      @status = params[:status].to_s
      @kind = params[:kind].to_s
      @owner = params[:owner].to_s.strip
      @overdue = ActiveModel::Type::Boolean.new.cast(params[:overdue]) == true
      @filters = { view: @view, q: @query, status: @status, kind: @kind, owner: @owner, overdue: @overdue ? "1" : nil }.compact_blank

      items = WorkItem.search(@query)
      items = case @view
      when "needs_review"
        items.where(status: "needs_review")
      when "unassigned"
        items.open.where(owner: nil)
      when "overdue"
        items.overdue
      when "all"
        items
      else
        items.open
      end
      items = items.open if @status == "open"
      items = items.where(status: @status) if @status.present? && !%w[open all].include?(@status)
      items = items.where(kind: @kind) if @kind.present?
      items = @owner == "unassigned" ? items.where(owner: nil) : items.where(owner: @owner) if @owner.present?
      items = items.overdue if @overdue

      @owners = WorkItem.where.not(owner: [ nil, "" ]).distinct.order(:owner).pluck(:owner)
      @total_count = WorkItem.count
      @filtered_count = items.count
      @total_pages = [ (@filtered_count + PAGE_SIZE - 1) / PAGE_SIZE, 1 ].max
      @page = params[:page].to_s.to_i.clamp(1, @total_pages)
      @work_items = items.includes(:conversation, :idea_capture).for_queue.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
      @first_result = @filtered_count.zero? ? 0 : (@page - 1) * PAGE_SIZE + 1
      @last_result = [ @page * PAGE_SIZE, @filtered_count ].min
      @queue_counts = {
        open: WorkItem.open.count,
        needs_review: WorkItem.where(status: "needs_review").count,
        unassigned: WorkItem.open.where(owner: nil).count,
        overdue: WorkItem.overdue.count
      }
    end

    def show
      @event_count = @work_item.events.count
      @events = @work_item.events.reorder(created_at: :desc, id: :desc).limit(EVENT_LIMIT)
      @handoffs = @work_item.work_item_handoffs.order(created_at: :desc, id: :desc).limit(20)
      @blocking_handoff = @handoffs.find do |handoff|
        handoff.delivery_uncertain? || (%w[pending_approval approved].include?(handoff.status) && handoff.revision_current?)
      end
    end

    def new
      @work_item = WorkItem.new(kind: "request", priority: "normal", status: "needs_review", intake_source: "web")
    end

    def create
      @work_item = WorkItem.new(create_params.merge(intake_source: "web", status: "needs_review", audit_actor: "admin"))
      if @work_item.save
        redirect_to admin_work_item_path(@work_item), notice: "Work item captured for review."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      WorkItemUpdateService.new(work_item: @work_item, attributes: update_params.to_h, actor: "admin").call
      redirect_to admin_work_item_path(@work_item), notice: "Work item updated."
    rescue ActiveRecord::RecordInvalid => error
      @work_item = error.record
      render :edit, status: :unprocessable_entity
    rescue ActiveRecord::StaleObjectError
      submitted = update_params.except(:lock_version).to_h
      @work_item.reload
      @unsaved_changes = submitted.reject { |field, value| @work_item.public_send(field).to_s == value.to_s }
      @work_item.errors.add(:base, "This work item changed while you were editing. Review the latest values and apply your changes again.")
      render :edit, status: :conflict
    end

    private

    def load_work_item
      @work_item = WorkItem.includes(:conversation, :idea_capture).find(params[:id])
    end

    def create_params
      params.require(:work_item).permit(:title, :kind, :description, :next_step, :owner, :priority, :due_on)
    end

    def update_params
      params.require(:work_item).permit(:title, :kind, :description, :next_step, :owner, :priority, :status, :due_on, :resolution_note, :lock_version)
    end
  end
end
