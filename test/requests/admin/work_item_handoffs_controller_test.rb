require "test_helper"

module Admin
  class WorkItemHandoffsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @item = WorkItem.create!(title: "Review reporting handoff", intake_source: "web", next_step: "Confirm the report owner")
    end

    test "preparation approval and simulated delivery are separate requests" do
      assert_difference -> { WorkItemHandoff.count }, 1 do
        post admin_work_item_handoffs_path(@item), params: { simulate: "1", destination_url: "https://ignored.example.test", prepared_by: "spoofed" }
      end
      assert_redirected_to admin_work_item_path(@item)
      handoff = @item.work_item_handoffs.last
      assert_equal "pending_approval", handoff.status
      assert_equal "admin", handoff.prepared_by
      assert handoff.dry_run?

      get admin_work_item_path(@item)
      assert_response :success
      assert_select "input[type=submit][value='Prepare handoff']", count: 0
      assert_select "a[href='#handoff-#{handoff.id}']"

      post deliver_admin_work_item_handoff_path(@item, handoff)
      assert_redirected_to admin_work_item_path(@item)
      assert_equal "pending_approval", handoff.reload.status
      assert_match(/approved handoff/, flash[:alert])

      post approve_admin_work_item_handoff_path(@item, handoff), params: { reviewer: "spoofed" }
      assert_redirected_to admin_work_item_path(@item)
      assert_equal "approved", handoff.reload.status
      assert_equal "admin", handoff.approved_by

      post deliver_admin_work_item_handoff_path(@item, handoff)
      assert_redirected_to admin_work_item_path(@item)
      assert handoff.reload.simulated?
      assert_equal "needs_review", @item.reload.status
      assert_nil @item.resolved_at
    end

    test "changing work invalidates a prepared approval" do
      handoff = prepare_simulation
      @item.update!(owner: "New owner")

      post approve_admin_work_item_handoff_path(@item, handoff)

      assert_redirected_to admin_work_item_path(@item)
      assert_equal "cancelled", handoff.reload.status
      assert_match(/changed/, flash[:alert])
    end

    test "nested actions cannot select another work item's handoff" do
      handoff = prepare_simulation
      other = WorkItem.create!(title: "Other request")

      post approve_admin_work_item_handoff_path(other, handoff)

      assert_response :not_found
      assert_equal "pending_approval", handoff.reload.status
    end

    test "cancellation retains the reviewed snapshot" do
      handoff = prepare_simulation
      snapshot = handoff.payload.deep_dup

      post cancel_admin_work_item_handoff_path(@item, handoff)

      assert_redirected_to admin_work_item_path(@item)
      assert_equal "cancelled", handoff.reload.status
      assert_equal snapshot, handoff.payload
    end

    test "uncertain delivery requires reconciliation evidence and does not resolve work" do
      handoff = prepare_simulation
      handoff.update!(status: "unknown", error: "Delivery outcome needs review")

      get admin_work_item_path(@item)
      assert_response :success
      assert_select "h4", text: "Reconcile uncertain delivery"
      assert_select "textarea[name='handoff[note]'][required]"
      assert_select "input[type=submit][value='Prepare handoff']", count: 0

      post reconcile_admin_work_item_handoff_path(@item, handoff), params: { handoff: { outcome: "not_delivered", note: "" } }
      assert_redirected_to admin_work_item_path(@item)
      assert_equal "unknown", handoff.reload.status

      post reconcile_admin_work_item_handoff_path(@item, handoff), params: { handoff: { outcome: "not_delivered", note: "Checked the receiving queue and confirmed no record exists." }, reviewer: "spoofed" }
      assert_redirected_to admin_work_item_path(@item)
      assert_equal "failed", handoff.reload.status
      assert_equal "admin", handoff.reconciled_by
      assert_equal "needs_review", @item.reload.status
    end

    test "handoff mutations require configured admin authentication" do
      handoff = prepare_simulation
      AppSetting.create!(key: "ADMIN_AUTH_REQUIRED", value: "true")

      assert_no_difference -> { WorkItemHandoff.count } do
        post admin_work_item_handoffs_path(@item), params: { simulate: "1" }
        assert_response :unauthorized
      end
      post approve_admin_work_item_handoff_path(@item, handoff)
      assert_response :unauthorized
      assert_equal "pending_approval", handoff.reload.status
    end

    private

    def prepare_simulation
      result = WorkItemHandoffService.new(work_item: @item).prepare(prepared_by: "admin", simulate: true)
      assert result.ok, result.error
      result.handoff
    end
  end
end
