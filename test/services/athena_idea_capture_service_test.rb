require "test_helper"

class AthenaIdeaCaptureServiceTest < ActiveSupport::TestCase
  test "capturing an idea creates linked review work without changing the tool contract" do
    result = nil
    without_external_reporting do
      assert_difference [ -> { IdeaCapture.count }, -> { WorkItem.count }, -> { WorkItemEvent.count } ], 1 do
        result = capture(title: "Investigate intake routing", problem: "Staff review the request twice.", next_step: "Review one sample.")
      end
    end

    assert result[:ok]
    assert_equal "capture_idea", result[:command]
    assert_equal "idea_captured", result[:action]
    item = WorkItem.find(result[:work_item_id])
    assert_equal result[:idea_capture_id], item.idea_capture_id
    assert_equal conversations(:one).id, item.conversation_id
    assert_equal "needs_review", item.status
    assert_equal "voice_capture", item.events.first.actor
    assert_equal "captured", item.idea_capture.status
  end

  test "repeated voice capture preserves operator work while updating source evidence" do
    without_external_reporting do
      first_result = capture(title: "Initial source title", next_step: "Initial suggestion")
      item = WorkItem.find(first_result[:work_item_id])
      WorkItemUpdateService.new(
        work_item: item, attributes: { title: "Operator-triaged title", owner: "Operations", status: "waiting", lock_version: item.lock_version }, actor: "admin"
      ).call

      assert_no_difference [ -> { WorkItem.count }, -> { WorkItemEvent.count } ] do
        second_result = capture(title: "Updated source title", next_step: "A new voice suggestion")
        assert_equal first_result[:work_item_id], second_result[:work_item_id]
      end

      assert_equal "Updated source title", item.idea_capture.reload.title
      assert_equal "Operator-triaged title", item.reload.title
      assert_equal "Operations", item.owner
      assert_equal "waiting", item.status
      assert_equal "Initial suggestion", item.next_step
    end
  end

  test "a failed conversion rolls back idea capture before reporting" do
    original_factory = WorkItemFromIdeaService.method(:new)
    failing_service = Object.new
    failing_service.define_singleton_method(:call) { raise "Work intake audit failed" }
    WorkItemFromIdeaService.define_singleton_method(:new) { |**_kwargs| failing_service }

    assert_no_difference [ -> { IdeaCapture.count }, -> { WorkItem.count }, -> { WorkItemEvent.count }, -> { SidecarEvent.count } ] do
      error = assert_raises(RuntimeError) { capture(title: "This capture must roll back") }
      assert_equal "Work intake audit failed", error.message
    end
  ensure
    WorkItemFromIdeaService.define_singleton_method(:new) { |*args, **kwargs, &block| original_factory.call(*args, **kwargs, &block) }
  end

  private

  def capture(payload)
    AthenaIdeaCaptureService.new(conversation: conversations(:one), payload: payload).call
  end

  def without_external_reporting
    original_factory = AthenaIdeaDiscordReportService.method(:new)
    reporter = Struct.new(:call).new({ ok: false, skipped: true, error: "Reporting disabled for this test." })
    AthenaIdeaDiscordReportService.define_singleton_method(:new) { |**_kwargs| reporter }
    yield
  ensure
    AthenaIdeaDiscordReportService.define_singleton_method(:new) { |*args, **kwargs, &block| original_factory.call(*args, **kwargs, &block) }
  end
end
