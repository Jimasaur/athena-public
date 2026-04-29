require "test_helper"

class AthenaTranscriptEmailSidecarServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "queues approval for a completed call transcript" do
    conversation = conversations(:one)
    conversation.sidecar_events.destroy_all
    conversation.messages.destroy_all
    conversation.update!(status: "completed", summary: "Caller asked for a test follow-up.")
    conversation.customer.update!(
      name: "Jimmy",
      metadata: conversation.customer.metadata.merge("email" => "operator@example.com")
    )
    conversation.messages.create!(role: "assistant", content: "Hi Jimmy, I'm Athena.", sent_at: 2.minutes.ago)
    conversation.messages.create!(role: "user", content: "Please send me the transcript.", sent_at: 1.minute.ago)

    assert_enqueued_with(job: GemmaMailApprovalJob) do
      assert_difference "conversation.sidecar_events.where(kind: 'email_approval.queued').count", 1 do
        assert_difference "conversation.sidecar_events.where(kind: 'transcript_email.queued').count", 1 do
          result = AthenaTranscriptEmailSidecarService.new(conversation: conversation).call
          assert result[:ok]
          assert_equal "approval_requested", result[:delivery_status]
        end
      end
    end

    event = conversation.sidecar_events.where(kind: "email_approval.queued").order(:created_at).last
    assert_equal "athena-conversation-#{conversation.id}-transcript", event.payload["approval_id"]
    assert_equal "call_transcript", event.payload["category"]
    assert_equal "operator@example.com", event.payload["recipient"]
    assert_includes event.payload["body"], "Transcript:"
    assert_includes event.payload["body"], "Athena: Hi Jimmy"
    assert_includes event.payload["body"], "Caller: Please send me the transcript."
  end

  test "does not duplicate transcript approval" do
    conversation = conversations(:one)
    conversation.messages.create!(role: "user", content: "Hello", sent_at: Time.current)
    conversation.customer.update!(metadata: conversation.customer.metadata.merge("email" => "operator@example.com"))
    conversation.sidecar_events.create!(
      call_state: call_states(:one),
      source: "test",
      kind: "email_approval.queued",
      provider: "athena",
      payload: { approval_id: "athena-conversation-#{conversation.id}-transcript" },
      occurred_at: Time.current
    )

    assert_no_enqueued_jobs do
      result = AthenaTranscriptEmailSidecarService.new(conversation: conversation).call
      assert result[:skipped]
      assert_equal "Transcript email already exists.", result[:reason]
    end
  end
end
