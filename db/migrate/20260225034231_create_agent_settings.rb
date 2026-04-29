class CreateAgentSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_settings do |t|
      t.string :agent_id, null: false
      t.string :name
      t.text :system_prompt
      t.json :tools, default: []
      t.string :voice_id
      t.string :model
      t.string :webhook_url
      t.string :tool_url
      t.json :data, default: {}

      t.timestamps
    end

    add_index :agent_settings, :agent_id, unique: true
  end
end
