class AddAgentNameToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :agent_name, :string
  end
end
