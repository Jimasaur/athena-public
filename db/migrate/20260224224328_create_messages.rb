class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :messages, :sent_at
  end
end
