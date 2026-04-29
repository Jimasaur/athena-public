class CallEvent < ApplicationRecord
  belongs_to :conversation

  validates :twilio_call_sid, :status, presence: true

  after_create_commit :broadcast_created
  after_create_commit :broadcast_transcript, if: :post_call_transcript?
  before_destroy :clear_conversation_transcript

  private

  def clear_conversation_transcript
    return if conversation.transcript_call_event_id != id

    conversation.update_column(:transcript_call_event_id, nil)
  end

  def broadcast_created
    broadcast_append_to(
      conversation,
      target: ActionView::RecordIdentifier.dom_id(conversation, :call_events),
      partial: "admin/conversations/call_event",
      locals: { call_event: self }
    )
  end

  def broadcast_transcript
    broadcast_replace_to(
      conversation,
      target: ActionView::RecordIdentifier.dom_id(conversation, :transcript),
      partial: "admin/conversations/transcript",
      locals: { conversation: conversation, transcript_event: self }
    )
  end

  def post_call_transcript?
    data.is_a?(Hash) && data["type"] == "post_call_transcription"
  end
end
