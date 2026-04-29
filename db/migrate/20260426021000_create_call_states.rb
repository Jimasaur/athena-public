class CreateCallStates < ActiveRecord::Migration[8.1]
  def change
    create_table :call_states do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :call_id, null: false
      t.string :provider
      t.string :space
      t.string :use_case_slug
      t.string :status, null: false, default: "initializing"
      t.json :state, default: {}
      t.string :review_status, null: false, default: "pending"

      t.timestamps
    end

    add_index :call_states, :call_id, unique: true
    add_index :call_states, :provider
    add_index :call_states, :review_status
    add_index :call_states, :use_case_slug
  end
end
