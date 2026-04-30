class CallAudioChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(id: params[:conversation_id])
    reject unless authorized_conversation?(conversation)

    stream_for conversation
  end

  private

  def authorized_conversation?(conversation)
    return false unless connection.admin_cable_session
    return false unless conversation&.status == "in_progress"

    token_conversation_id = LiveAudioAuthorization.conversation_id_from_token(params[:token])
    token_conversation_id == conversation.id
  end
end
