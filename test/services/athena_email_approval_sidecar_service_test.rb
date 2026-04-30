require "test_helper"

class AthenaEmailApprovalSidecarServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "creates Gemma Mail approval from completed call transcript" do
    conversation = conversations(:one)
    conversation.sidecar_events.destroy_all
    conversation.messages.destroy_all
    conversation.customer.update!(metadata: conversation.customer.metadata.merge("email" => "operator@example.com"))
    conversation.messages.create!(role: "assistant", content: "Sure, here's the draft subject Weather forecast for tomorrow", sent_at: 4.minutes.ago)
    conversation.messages.create!(role: "assistant", content: "Jordan, here is the weather placeholder for White Bear Lake tomorrow.", sent_at: 3.minutes.ago)
    conversation.messages.create!(role: "user", content: "Email me this and send me approval.", sent_at: 2.minutes.ago)

    assert_enqueued_with(job: GemmaMailApprovalJob) do
      assert_difference "SidecarEvent.where(kind: 'email_approval.queued').count", 1 do
        assert_difference "SidecarEvent.where(kind: 'email_approval.auto_detected').count", 1 do
          result = AthenaEmailApprovalSidecarService.new(conversation: conversation).call
          assert result[:ok]
          assert_equal "approval_requested", result[:delivery_status]
        end
      end
    end

    event = conversation.sidecar_events.where(kind: "email_approval.queued").order(:created_at).last
    assert_equal "operator@example.com", event.payload["recipient"]
    assert_equal "Weather forecast for tomorrow", event.payload["subject"]
    assert_includes event.payload["body"], "White Bear Lake"
    refute_includes event.payload["body"], "Here's the draft subject"
  end

  test "does not create duplicate approval for the same conversation" do
    conversation = conversations(:one)
    conversation.messages.create!(role: "user", content: "Email me a summary and send approval.", sent_at: Time.current)
    conversation.sidecar_events.create!(
      call_state: call_states(:one),
      source: "test",
      kind: "email_approval.queued",
      provider: "athena",
      payload: { approval_id: "athena-conversation-#{conversation.id}" },
      occurred_at: Time.current
    )

    assert_no_enqueued_jobs do
      result = AthenaEmailApprovalSidecarService.new(conversation: conversation).call
      assert result[:skipped]
      assert_equal "Email approval already exists.", result[:reason]
    end
  end
end
