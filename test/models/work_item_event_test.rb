require "test_helper"

class WorkItemEventTest < ActiveSupport::TestCase
  test "audit events require a source actor type and object details" do
    event = WorkItemEvent.new(event_type: "invalid type", actor: "", details: [])

    assert_not event.valid?
    %i[work_item event_type actor details].each { |field| assert event.errors[field].present? }
  end

  test "bounded custom lifecycle events support downstream handoff evidence" do
    item = WorkItem.create!(title: "Review staff follow-up")
    event = item.events.create!(event_type: "handoff.prepared", actor: "admin", details: { handoff_id: 17, dry_run: true })

    assert_equal item, event.work_item
    assert_equal 17, event.details["handoff_id"]
    assert_equal true, event.details["dry_run"]
    assert_equal "needs_review", item.reload.status
  end
end
