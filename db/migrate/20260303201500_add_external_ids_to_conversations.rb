class AddExternalIdsToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :twilio_call_sid, :string unless column_exists?(:conversations, :twilio_call_sid)
    add_index :conversations, :twilio_call_sid unless index_exists?(:conversations, :twilio_call_sid)
  end
end
