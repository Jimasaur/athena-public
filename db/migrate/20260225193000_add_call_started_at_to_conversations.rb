class AddCallStartedAtToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :call_started_at, :datetime
  end
end
