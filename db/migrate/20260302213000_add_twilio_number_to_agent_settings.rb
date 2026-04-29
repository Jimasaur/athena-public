class AddTwilioNumberToAgentSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :agent_settings, :twilio_number, :string
    add_index :agent_settings, :twilio_number
  end
end
