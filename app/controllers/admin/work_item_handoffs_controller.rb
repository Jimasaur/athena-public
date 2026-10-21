module Admin
  class WorkItemHandoffsController < BaseController
    before_action :load_work_item
    before_action :load_handoff, except: :create

    def create
      result = WorkItemHandoffService.new(work_item: @work_item).prepare(
        prepared_by: "admin",
        simulate: params[:simulate] == "1"
      )
      finish(result, "Handoff prepared for review.")
    end

    def approve
      finish(handoff_service.approve(reviewer: "admin"), "Handoff approved. Delivery requires a separate action.")
    end

    def deliver
      finish(handoff_service.deliver, "Delivery attempt recorded. Work resolution is unchanged.")
    end

    def cancel
      finish(handoff_service.cancel(reviewer: "admin"), "Handoff cancelled.")
    end

    def reconcile
      details = params.require(:handoff).permit(:outcome, :note)
      finish(
        handoff_service.reconcile(outcome: details[:outcome], reviewer: "admin", note: details[:note]),
        "Delivery reconciliation recorded. Work resolution is unchanged."
      )
    end

    private

    def load_work_item
      @work_item = WorkItem.find(params[:work_item_id])
    end

    def load_handoff
      @handoff = @work_item.work_item_handoffs.find(params[:id])
    end

    def handoff_service
      WorkItemHandoffService.new(handoff: @handoff)
    end

    def finish(result, notice)
      if result.ok
        redirect_to admin_work_item_path(@work_item), notice: notice
      else
        redirect_to admin_work_item_path(@work_item), alert: result.error
      end
    end
  end
end
