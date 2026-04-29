class AthenaTranscriptEmailJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, call_event_id = nil)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    call_event = CallEvent.find_by(id: call_event_id) if call_event_id.present?
    AthenaTranscriptEmailSidecarService.new(conversation: conversation, call_event: call_event).call
  end
end
