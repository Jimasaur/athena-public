class CreateActionDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :action_drafts do |t|
      t.references :call_state, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false, default: "pending_approval"
      t.string :created_by, null: false
      t.json :recipient, default: {}
      t.json :content, default: {}
      t.boolean :approval_required, null: false, default: true
      t.string :approved_by
      t.datetime :approved_at
      t.json :external_side_effect, default: {}

      t.timestamps
    end

    add_index :action_drafts, :kind
    add_index :action_drafts, :status
    add_index :action_drafts, :created_by
  end
end
