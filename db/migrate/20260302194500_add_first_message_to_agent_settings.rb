class AddFirstMessageToAgentSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :agent_settings, :first_message, :text
  end
end
