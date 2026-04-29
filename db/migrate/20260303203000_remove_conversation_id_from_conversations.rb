class RemoveConversationIdFromConversations < ActiveRecord::Migration[7.1]
  def change
    remove_index :conversations, :conversation_id if index_exists?(:conversations, :conversation_id)
    remove_column :conversations, :conversation_id, :string
  end
end
