require "test_helper"

class WorkItemUpdateServiceTest < ActiveSupport::TestCase
  setup do
    @work_item = WorkItem.create!(title: "Review the intake request")
  end

  test "an edit saves actual changes and actor with one versioned audit event" do
    assert_difference -> { @work_item.events.count }, 1 do
      result = update_work_item(owner: "Operations", priority: "high", next_step: "Review the source conversation")
      assert_same @work_item, result
    end

    assert_equal 1, @work_item.lock_version
    event = @work_item.events.last
    assert_equal "updated", event.event_type
    assert_equal "admin", event.actor
    assert_equal [ nil, "Operations" ], event.details.dig("changes", "owner")
    assert_equal [ "normal", "high" ], event.details.dig("changes", "priority")
    assert_equal 1, event.details["lock_version"]
    assert_not event.details["changes"].key?("updated_at")
  end

  test "an unchanged form does not create history or consume a version" do
    before_update = @work_item.updated_at
    assert_no_difference -> { @work_item.events.count } do
      update_work_item(title: @work_item.title, priority: @work_item.priority)
    end

    assert_equal 0, @work_item.reload.lock_version
    assert_equal before_update, @work_item.updated_at
  end

  test "stale and missing versions cannot overwrite current operator work" do
    stale_version = @work_item.lock_version
    update_work_item(owner: "Current owner")

    [ stale_version, nil, "", "1x", "-1" ].each do |version|
      assert_no_difference -> { @work_item.events.count } do
        assert_raises(ActiveRecord::StaleObjectError) do
          WorkItemUpdateService.new(
            work_item: @work_item, attributes: { owner: "Stale edit", lock_version: version }, actor: "admin"
          ).call
        end
      end
      assert_equal "Current owner", @work_item.reload.owner
    end
  end

  test "a stale loaded model is compared against the submitted database version" do
    separate_copy = WorkItem.find(@work_item.id)
    update_work_item(owner: "First operator")

    WorkItemUpdateService.new(
      work_item: separate_copy, attributes: { owner: "Second operator", lock_version: @work_item.lock_version }, actor: "admin"
    ).call

    assert_equal "Second operator", separate_copy.reload.owner
    assert_equal 2, separate_copy.lock_version
  end

  test "invalid resolution does not update the record or its history" do
    assert_no_difference -> { @work_item.events.count } do
      assert_raises(ActiveRecord::RecordInvalid) { update_work_item(status: "resolved", resolution_note: "  ") }
    end

    assert_equal "needs_review", @work_item.reload.status
    assert_nil @work_item.resolved_at
    assert_equal 0, @work_item.lock_version
  end

  test "resolution and reopening each preserve status and timestamp history" do
    update_work_item(status: "resolved", resolution_note: "Staff verified completion.")
    resolved_at = @work_item.resolved_at
    update_work_item(status: "ready")

    assert_nil @work_item.resolved_at
    assert_equal 3, @work_item.events.count
    assert_equal [ "resolved", "ready" ], @work_item.events.last.details.dig("changes", "status")
    assert_equal resolved_at.as_json, @work_item.events.last.details.dig("changes", "resolved_at", 0)
  end

  test "uneditable provenance and demo fields are refused" do
    assert_raises(ActiveRecord::RecordInvalid) { update_work_item(intake_source: "voice", demo: true, idea_capture_id: 123) }
    assert_equal "manual", @work_item.reload.intake_source
    assert_not @work_item.demo?
    assert_nil @work_item.idea_capture_id
    assert_equal 1, @work_item.events.count
  end

  test "audit insertion failure rolls back the record and version together" do
    assert_no_difference -> { @work_item.events.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        WorkItemUpdateService.new(
          work_item: @work_item, attributes: { title: "This update must roll back", lock_version: @work_item.lock_version }, actor: "x" * 121
        ).call
      end
    end

    assert_equal "Review the intake request", @work_item.reload.title
    assert_equal 0, @work_item.lock_version
  end

  private

  def update_work_item(attributes)
    WorkItemUpdateService.new(
      work_item: @work_item, attributes: attributes.merge(lock_version: @work_item.lock_version), actor: "admin"
    ).call
  end
end
