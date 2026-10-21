require "test_helper"

class WorkItemTest < ActiveSupport::TestCase
  test "standalone intake has explicit defaults and an attributed creation event" do
    work_item = WorkItem.create!(title: "Review an incoming request", audit_actor: "admin")

    assert_nil work_item.conversation
    assert_nil work_item.idea_capture
    assert_equal "request", work_item.kind
    assert_equal "needs_review", work_item.status
    assert_equal "normal", work_item.priority
    assert_equal "manual", work_item.intake_source
    assert_equal 0, work_item.lock_version
    assert_not work_item.demo?
    assert work_item.open?
    assert_equal 1, work_item.events.count
    event = work_item.events.first
    assert_equal "created", event.event_type
    assert_equal "admin", event.actor
    assert_equal [ nil, work_item.title ], event.details.dig("changes", "title")
    assert_equal [ nil, "needs_review" ], event.details.dig("changes", "status")
    assert_equal 0, event.details["lock_version"]
  end

  test "intake validates meaningful lengths vocabulary and dates" do
    work_item = WorkItem.new(
      title: "  ", kind: "other", priority: "immediately", status: "sent", intake_source: "email",
      description: "x" * (WorkItem::DESCRIPTION_MAX_LENGTH + 1),
      owner: "x" * (WorkItem::OWNER_MAX_LENGTH + 1),
      next_step: "x" * (WorkItem::NEXT_STEP_MAX_LENGTH + 1),
      due_on: "not-a-date"
    )

    assert_not work_item.valid?
    %i[title kind priority status intake_source description owner next_step due_on].each do |field|
      assert work_item.errors[field].present?, field.to_s
    end
    work_item.title = "x" * (WorkItem::TITLE_MAX_LENGTH + 1)
    assert_not work_item.valid?
    assert work_item.errors[:title].present?
  end

  test "blank owner becomes unassigned and multiline context is preserved" do
    work_item = WorkItem.create!(title: "  Review   intake  ", owner: "   ", description: "  First line\nSecond line  ")

    assert_equal "Review intake", work_item.title
    assert_nil work_item.owner
    assert_equal "First line\nSecond line", work_item.description
  end

  test "resolving requires a note and reopening preserves recorded resolution history" do
    work_item = WorkItem.create!(title: "Investigate intake issue")

    assert_not work_item.update(status: "resolved")
    assert work_item.errors[:resolution_note].present?
    assert_nil work_item.reload.resolved_at

    work_item.update!(status: "resolved", resolution_note: "Verified the corrected intake path.", audit_actor: "admin")
    resolved_at = work_item.resolved_at
    assert work_item.resolved?
    assert resolved_at.present?
    resolved_event = work_item.events.last
    assert_equal "status_changed", resolved_event.event_type
    assert_equal [ "needs_review", "resolved" ], resolved_event.details.dig("changes", "status")
    assert_equal "admin", resolved_event.actor

    work_item.update!(status: "in_progress", audit_actor: "admin")
    assert_nil work_item.resolved_at
    assert_equal "Verified the corrected intake path.", work_item.resolution_note
    assert_equal [ "resolved", "in_progress" ], work_item.events.last.details.dig("changes", "status")
    assert_equal resolved_at.as_json, work_item.events.last.details.dig("changes", "resolved_at", 0)
    assert_equal 3, work_item.events.count
  end

  test "normal model updates also append history and audit failure rolls back the edit" do
    work_item = WorkItem.create!(title: "Review original request")
    work_item.update!(owner: "Intake team")

    assert_equal "updated", work_item.events.last.event_type
    assert_equal "system", work_item.events.last.actor
    assert_equal [ nil, "Intake team" ], work_item.events.last.details.dig("changes", "owner")
    original_version = work_item.lock_version

    assert_no_difference -> { work_item.events.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        work_item.update!(title: "An edit without valid audit attribution", audit_actor: "x" * 121)
      end
    end
    assert_equal "Review original request", work_item.reload.title
    assert_equal original_version, work_item.lock_version
  end

  test "deleting source records preserves independent work and its audit history" do
    conversation = conversations(:one)
    idea = IdeaCapture.create!(conversation: conversation, title: "Source opportunity")
    work_item = WorkItem.create!(title: "Preserve this work", conversation: conversation, idea_capture: idea)
    creation_event_id = work_item.events.first.id

    idea.destroy!
    assert_nil work_item.reload.idea_capture_id
    assert_equal conversation.id, work_item.conversation_id

    conversation.destroy!
    assert_nil work_item.reload.conversation_id
    assert_equal creation_event_id, work_item.events.first.id
    assert_equal idea.id, work_item.events.first.details.dig("changes", "idea_capture_id", 1)
  end

  test "an idea has at most one linked item while standalone items remain independent" do
    idea = IdeaCapture.create!(conversation: conversations(:one), title: "One source idea")
    WorkItem.create!(title: "First linked work", idea_capture: idea)
    duplicate = WorkItem.new(title: "Duplicate linked work", idea_capture: idea)

    assert_not duplicate.valid?
    assert duplicate.errors[:idea_capture_id].present?
    assert_difference -> { WorkItem.count }, 2 do
      WorkItem.create!(title: "First standalone work")
      WorkItem.create!(title: "Second standalone work")
    end
  end

  test "search covers work context while treating SQL wildcards literally" do
    item = WorkItem.create!(
      title: "Investigate intake", owner: "Team_One", description: "Check authorization routing",
      next_step: "Review a sample", resolution_note: "Potential 10% improvement"
    )

    %w[INTAKE authorization sample Team_One 10%].each do |query|
      assert_includes WorkItem.search(query), item
    end
    assert_not_includes WorkItem.search("Team%One"), item
    assert_not_includes WorkItem.search("missing"), item
    assert_equal WorkItem.count, WorkItem.search("  ").count
  end

  test "overdue contains only open work before today" do
    overdue = WorkItem.create!(title: "Overdue waiting item", due_on: Date.current.yesterday, status: "waiting")
    due_today = WorkItem.create!(title: "Due today item", due_on: Date.current)
    resolved = WorkItem.create!(title: "Resolved old item", due_on: Date.current.yesterday, status: "resolved", resolution_note: "Reviewed and completed.")
    archived = WorkItem.create!(title: "Archived old item", due_on: Date.current.yesterday, status: "archived")

    assert_includes WorkItem.overdue, overdue
    [ due_today, resolved, archived ].each { |item| assert_not_includes WorkItem.overdue, item }
    assert overdue.overdue?
    assert_not due_today.overdue?
    assert_not resolved.open?
    assert_not archived.open?
  end

  test "queue order is priority then due date then stable oldest work first" do
    normal_undated = WorkItem.create!(title: "Normal undated item", created_at: 10.days.ago)
    urgent = WorkItem.create!(title: "Urgent undated item", priority: "urgent")
    normal_later = WorkItem.create!(title: "Normal later due item", due_on: Date.current.tomorrow)
    high = WorkItem.create!(title: "High priority old item", priority: "high", due_on: Date.current.yesterday)
    normal_first = WorkItem.create!(title: "Normal oldest due item", due_on: Date.current, created_at: 2.days.ago)
    normal_second = WorkItem.create!(title: "Normal newest due item", due_on: Date.current, created_at: 1.day.ago)
    low = WorkItem.create!(title: "Low priority old item", priority: "low", due_on: 5.days.ago.to_date)

    assert_equal [ urgent, high, normal_first, normal_second, normal_later, normal_undated, low ].map(&:id), WorkItem.for_queue.pluck(:id)
    assert_equal WorkItem.for_queue.pluck(:id), WorkItem.order(id: :desc).for_queue.pluck(:id)
  end
end
