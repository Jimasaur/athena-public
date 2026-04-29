class RemoveModelAndWebhookUrlFromAgentSettings < ActiveRecord::Migration[8.1]
  def change
    remove_column :agent_settings, :model, :string
    remove_column :agent_settings, :webhook_url, :string
  end
end
