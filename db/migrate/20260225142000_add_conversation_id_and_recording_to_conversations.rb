class AddConversationIdAndRecordingToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :conversation_id, :string
    add_column :conversations, :recording_audio_base64, :text
    add_index :conversations, :conversation_id
  end
end
