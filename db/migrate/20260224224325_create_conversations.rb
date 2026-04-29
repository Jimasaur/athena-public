class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :status, null: false, default: "open"
      t.text :summary

      t.timestamps
    end

    add_index :conversations, :channel
    add_index :conversations, :status
  end
end
