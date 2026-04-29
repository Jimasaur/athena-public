class CallAudioChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(id: params[:conversation_id])
    reject unless conversation

    stream_for conversation
  end
end
