require "test_helper"

module Admin
  class WorkItemsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @item = WorkItem.create!(title: "Clarify weekly reporting request", kind: "request", description: "A reporting intake needs an owner", priority: "normal", intake_source: "web")
    end

    test "queue defaults to open work and combines content kind and ownership filters" do
      excluded = WorkItem.create!(title: "Archived reporting request", kind: "request", status: "archived")
      WorkItem.create!(title: "Assigned reporting issue", kind: "issue", owner: "Priya Shah")

      get admin_work_items_path, params: { q: "reporting", kind: "request", owner: "unassigned" }

      assert_response :success
      assert_select "h1", text: "Work queue"
      assert_select "tr[data-work-item-id]", count: 1
      assert_select "tr[data-work-item-id='#{@item.id}']"
      assert_select "tr[data-work-item-id='#{excluded.id}']", count: 0
      assert_select "label[for=q]", text: "Search work"
      assert_select "select[name=owner] option[selected]", text: "Unassigned"
      assert_select "a", text: "Workspace overview"
    end

    test "named views separate reviewed unassigned overdue and closed work" do
      overdue = WorkItem.create!(title: "Overdue assigned task", status: "ready", owner: "Nora Patel", due_on: Date.yesterday)
      closed = WorkItem.create!(title: "Finished request", status: "resolved", resolution_note: "The report was checked.", due_on: Date.yesterday)

      get admin_work_items_path(view: "overdue")
      assert_response :success
      assert_select "tr[data-work-item-id='#{overdue.id}']"
      assert_select "tr[data-work-item-id='#{closed.id}']", count: 0
      assert_select "tr[data-work-item-id='#{@item.id}']", count: 0

      get admin_work_items_path(view: "needs_review")
      assert_response :success
      assert_select "tr[data-work-item-id='#{@item.id}']"
      assert_select "tr[data-work-item-id='#{overdue.id}']", count: 0

      get admin_work_items_path(view: "all", status: "resolved")
      assert_response :success
      assert_select "tr[data-work-item-id]", count: 1
      assert_select "tr[data-work-item-id='#{closed.id}']"
    end

    test "pagination is bounded and retains filters" do
      26.times { |index| WorkItem.create!(title: "Reporting item #{index}", kind: "request") }

      get admin_work_items_path, params: { q: "reporting", kind: "request", page: "-1" }
      assert_response :success
      assert_select "tr[data-work-item-id]", count: 25
      assert_select "a[rel=next]" do |links|
        assert_includes links.first["href"], "kind=request"
        assert_includes links.first["href"], "q=reporting"
      end

      get admin_work_items_path, params: { q: "reporting", page: "99999999999999999999" }
      assert_response :success
      assert_select "tr[data-work-item-id]", count: 2
      assert_includes response.body, "Showing 26–27 of 27"
    end

    test "authenticated web intake creates only a work item and its audit event" do
      assert_no_difference -> { Conversation.count } do
        assert_no_difference -> { Customer.count } do
          assert_difference -> { WorkItem.count }, 1 do
            assert_difference -> { WorkItemEvent.count }, 1 do
              post admin_work_items_path, params: { work_item: {
                title: "Review a reporting handoff", kind: "issue", owner: "Priya Shah", priority: "high",
                description: "The report is missing its review step.", next_step: "Confirm ownership", due_on: Date.tomorrow.iso8601,
                intake_source: "voice", status: "resolved", conversation_id: conversations(:one).id, audit_actor: "spoofed"
              } }
            end
          end
        end
      end

      item = WorkItem.order(:id).last
      assert_redirected_to admin_work_item_path(item)
      assert_equal "web", item.intake_source
      assert_equal "needs_review", item.status
      assert_nil item.conversation_id
      assert_equal "admin", item.events.last.actor
    end

    test "invalid intake retains entered fields and validation messages" do
      assert_no_difference -> { WorkItem.count } do
        post admin_work_items_path, params: { work_item: { title: "", kind: "request", description: "Keep this context" } }
      end
      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /Title/
      assert_select "textarea[name='work_item[description]']", text: "Keep this context"
    end

    test "update audits ownership and resolution without changing source associations" do
      assert_difference -> { WorkItemEvent.count }, 1 do
        patch admin_work_item_path(@item), params: { work_item: {
          lock_version: @item.lock_version, owner: "Nora Patel", status: "resolved", resolution_note: "Reviewed and handed back to the requester.",
          intake_source: "voice", conversation_id: conversations(:two).id
        } }
      end

      assert_redirected_to admin_work_item_path(@item)
      assert_equal "resolved", @item.reload.status
      assert_equal "Nora Patel", @item.owner
      assert_not_nil @item.resolved_at
      assert_equal "web", @item.intake_source
      assert_nil @item.conversation_id
      assert_equal "admin", @item.events.last.actor
    end

    test "resolution requires a note" do
      patch admin_work_item_path(@item), params: { work_item: { lock_version: @item.lock_version, status: "resolved", resolution_note: "" } }

      assert_response :unprocessable_entity
      assert_equal "needs_review", @item.reload.status
      assert_select "[role=alert]", text: /Resolution note/
    end

    test "stale or missing versions cannot overwrite a newer decision" do
      stale_version = @item.lock_version
      @item.update!(owner: "Current owner")

      assert_no_difference -> { WorkItemEvent.count } do
        patch admin_work_item_path(@item), params: { work_item: { lock_version: stale_version, owner: "Stale owner" } }
      end
      assert_response :conflict
      assert_equal "Current owner", @item.reload.owner
      assert_select "input[name='work_item[lock_version]'][value='#{@item.lock_version}']"
      assert_select "[role=alert]", text: /changed while you were editing/
      assert_select "section[aria-label='Your unsaved submission']", text: /Stale owner/
      assert_select "input[name='work_item[owner]'][value='Current owner']"

      patch admin_work_item_path(@item), params: { work_item: { owner: "Missing version owner" } }
      assert_response :conflict
      assert_equal "Current owner", @item.reload.owner
    end

    test "detail includes source evidence ownership history and separate handoff controls" do
      get admin_work_item_path(@item)

      assert_response :success
      assert_select "h2", text: "Source evidence"
      assert_select "h2", text: "Ownership and timing"
      assert_select "h2", text: "Work history"
      assert_select "input[name=simulate][checked]"
      assert_includes response.body, "No source conversation is attached"
      assert_select "input[type=submit][value='Prepare handoff']"
    end

    test "intake and updates require admin authentication when enabled" do
      AppSetting.create!(key: "ADMIN_AUTH_REQUIRED", value: "true")

      get new_admin_work_item_path
      assert_response :unauthorized
      assert_no_difference -> { WorkItem.count } do
        post admin_work_items_path, params: { work_item: { title: "Unauthorized intake" } }
        assert_response :unauthorized
      end
      assert_no_difference -> { WorkItemEvent.count } do
        patch admin_work_item_path(@item), params: { work_item: { lock_version: @item.lock_version, owner: "Unauthorized owner" } }
        assert_response :unauthorized
      end
    end
  end
end
