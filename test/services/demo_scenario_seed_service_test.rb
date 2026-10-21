require "test_helper"

class DemoScenarioSeedServiceTest < ActiveSupport::TestCase
  test "seeds a complete deterministic scenario conversation" do
    scenario = DemoScenarioCatalog.fetch("rev-cycle-ideation-session")

    assert_difference -> { Conversation.count }, 1 do
      assert_difference -> { IdeaCapture.count }, 1 do
        @conversation = DemoScenarioSeedService.new(slug: scenario[:slug]).call
      end
    end

    assert_equal scenario[:summary], @conversation.summary
    assert_equal scenario[:agent_name], @conversation.agent_name
    assert_equal "completed", @conversation.status
    assert @conversation.transcript_call_event.present?
    assert_equal scenario[:transcript].size, @conversation.messages.count

    call_state = @conversation.call_state
    assert_equal scenario[:provider], call_state.provider
    assert_equal scenario[:slug], call_state.use_case_slug
    assert_equal scenario.dig(:intent, "label"), call_state.state.dig("intent", "label")
    assert_equal scenario[:next_best_question], call_state.state["next_best_question"]

    assert_equal 1, @conversation.action_drafts.count
    assert_equal 1, @conversation.idea_captures.count
    assert_equal 1, @conversation.work_items.count
    assert @conversation.work_items.first.demo?
    assert_equal @conversation.idea_captures.first.id, @conversation.work_items.first.idea_capture_id
    assert_equal scenario[:action_status], @conversation.action_drafts.first.status
    assert @conversation.sidecar_events.where(kind: "state_patch.applied").exists?
    assert @conversation.sidecar_events.where(kind: "summary.created").exists?
    assert @conversation.sidecar_events.where(kind: "idea_capture.captured").exists?
  end

  test "launching the same scenario replaces the previous demo conversation" do
    slug = "rev-cycle-ideation-session"
    first = DemoScenarioSeedService.new(slug: slug).call
    second = nil

    assert_no_difference -> { Conversation.where(twilio_call_sid: first.twilio_call_sid).count } do
      second = DemoScenarioSeedService.new(slug: slug).call
    end

    assert_not_equal first.id, second.id
    assert_equal 1, Conversation.where(twilio_call_sid: first.twilio_call_sid).count
    assert_equal 1, WorkItem.where(conversation_id: second.id).count
    assert_not WorkItem.where(conversation_id: first.id).exists?
  end

  test "resetting a demo replaces only work derived from that synthetic source" do
    first = DemoScenarioSeedService.new(slug: "rev-cycle-ideation-session").call
    derived_item_id = first.work_items.first.id
    manual = WorkItem.create!(title: "Staff-created independent follow-up", conversation: first, intake_source: "web")
    unrelated = WorkItem.create!(title: "Another conversation request", conversation: conversations(:two))

    assert_no_difference -> { WorkItem.count } do
      DemoScenarioSeedService.new(slug: "rev-cycle-ideation-session").call
    end

    assert_not WorkItem.exists?(derived_item_id)
    assert_nil manual.reload.conversation_id
    assert_equal conversations(:two).id, unrelated.reload.conversation_id
  end
end
