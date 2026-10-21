class CreateWorkItems < ActiveRecord::Migration[8.1]
  def change
    create_table :work_items do |t|
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :idea_capture, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.string :title, null: false, limit: 200
      t.string :kind, null: false, default: "request"
      t.text :description
      t.text :next_step
      t.string :owner, limit: 120
      t.string :priority, null: false, default: "normal"
      t.string :status, null: false, default: "needs_review"
      t.date :due_on
      t.text :resolution_note
      t.datetime :resolved_at
      t.string :intake_source, null: false, default: "manual"
      t.boolean :demo, null: false, default: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :work_items, [ :status, :priority, :due_on ]
    add_index :work_items, :owner
    add_index :work_items, :due_on
    add_check_constraint :work_items, "kind IN ('request', 'issue', 'opportunity', 'follow_up')", name: "work_items_valid_kind"
    add_check_constraint :work_items, "priority IN ('low', 'normal', 'high', 'urgent')", name: "work_items_valid_priority"
    add_check_constraint :work_items, "status IN ('needs_review', 'ready', 'in_progress', 'waiting', 'resolved', 'archived')", name: "work_items_valid_status"
    add_check_constraint :work_items, "intake_source IN ('voice', 'web', 'manual')", name: "work_items_valid_intake_source"

    create_table :work_item_events do |t|
      t.references :work_item, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :event_type, null: false, limit: 80
      t.string :actor, null: false, limit: 120
      t.json :details, null: false, default: {}
      t.timestamps
    end

    add_index :work_item_events, [ :work_item_id, :created_at, :id ]
  end
end
