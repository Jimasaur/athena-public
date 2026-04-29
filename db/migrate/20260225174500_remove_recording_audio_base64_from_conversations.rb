class RemoveRecordingAudioBase64FromConversations < ActiveRecord::Migration[8.1]
  def change
    remove_column :conversations, :recording_audio_base64, :text
  end
end
