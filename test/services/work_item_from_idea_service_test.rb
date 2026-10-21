require "test_helper"

class WorkItemFromIdeaServiceTest < ActiveSupport::TestCase
  setup do
    @idea = IdeaCapture.create!(
      conversation: conversations(:one), title: "Review authorization routing", problem: "The request is routed twice.",
      proposed_solution: "Check the intake rule.", impact: "Avoid duplicated staff review.", next_step: "Assign a pilot owner."
    )
  end

  test "conversion creates one attributed opportunity using source evidence" do
    item = nil
    assert_difference -> { WorkItem.count }, 1 do
      assert_difference -> { WorkItemEvent.count }, 1 do
        item = WorkItemFromIdeaService.new(idea_capture: @idea).call
      end
    end

    assert_equal @idea.id, item.idea_capture_id
    assert_equal @idea.conversation_id, item.conversation_id
    assert_equal @idea.title, item.title
    assert_equal "opportunity", item.kind
    assert_equal "voice", item.intake_source
    assert_equal "needs_review", item.status
    assert_nil item.owner
    assert_not item.demo?
    assert_includes item.description, @idea.problem
    assert_includes item.description, @idea.proposed_solution
    assert_includes item.description, @idea.impact
    assert_equal "capture", item.events.first.actor
    assert_equal "captured", @idea.reload.status
  end

  test "conversion remains idempotent and never overwrites operator changes" do
    item = WorkItemFromIdeaService.new(idea_capture: @idea).call
    WorkItemUpdateService.new(
      work_item: item, attributes: { title: "Staff triaged this request", owner: "Operations", status: "in_progress", lock_version: item.lock_version }, actor: "admin"
    ).call
    @idea.update!(title: "A later capture changed this title", next_step: "A later suggestion")

    assert_no_difference [ -> { WorkItem.count }, -> { WorkItemEvent.count } ] do
      repeated = WorkItemFromIdeaService.new(idea_capture: @idea, actor: "backfill").call
      assert_equal item.id, repeated.id
    end

    assert_equal "Staff triaged this request", item.reload.title
    assert_equal "Operations", item.owner
    assert_equal "in_progress", item.status
    assert_equal "Assign a pilot owner.", item.next_step
    assert_equal 1, item.lock_version
  end

  test "reviewed and archived ideas keep their review meaning after conversion" do
    %w[reviewed archived].each do |status|
      idea = IdeaCapture.create!(conversation: conversations(:one), title: "Previously #{status} source", status: status)
      item = WorkItemFromIdeaService.new(idea_capture: idea, actor: "backfill").call

      assert_equal status, idea.reload.status
      assert_equal "needs_review", item.status
      assert_equal "backfill", item.events.first.actor
    end
  end

  test "conversion bounds display fields without deleting the original source evidence" do
    @idea.update!(title: "A" * 300, problem: "P" * 25_000, next_step: "N" * 3_000)
    item = WorkItemFromIdeaService.new(idea_capture: @idea).call

    assert_equal WorkItem::TITLE_MAX_LENGTH, item.title.length
    assert_equal WorkItem::DESCRIPTION_MAX_LENGTH, item.description.length
    assert_equal WorkItem::NEXT_STEP_MAX_LENGTH, item.next_step.length
    assert_equal 300, @idea.reload.title.length
    assert_equal 25_000, @idea.problem.length

    other = IdeaCapture.create!(conversation: conversations(:one), title: "AI")
    assert WorkItemFromIdeaService.new(idea_capture: other).call.valid?
  end

  test "synthetic source markers propagate and source channel is retained" do
    @idea.conversation.update!(twilio_call_sid: "DEMO-work-intake")
    assert WorkItemFromIdeaService.new(idea_capture: @idea).call.demo?

    web_source = Conversation.create!(customer: customers(:one), channel: "web", status: "open")
    web_idea = IdeaCapture.create!(conversation: web_source, title: "Synthetic web opportunity", payload: { demo: true })
    item = WorkItemFromIdeaService.new(idea_capture: web_idea).call
    assert item.demo?
    assert_equal "web", item.intake_source
  end

  test "conversion requires a persisted source idea" do
    assert_raises(ArgumentError) { WorkItemFromIdeaService.new(idea_capture: nil).call }
    assert_raises(ArgumentError) { WorkItemFromIdeaService.new(idea_capture: IdeaCapture.new(title: "Unsaved source")).call }
  end
end
