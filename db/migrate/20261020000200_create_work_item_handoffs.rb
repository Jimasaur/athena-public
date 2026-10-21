class CreateWorkItemHandoffs < ActiveRecord::Migration[8.1]
  def change
    create_table :work_item_handoffs do |t|
      t.references :work_item, null: false, foreign_key: true
      t.json :payload, null: false, default: {}
      t.string :payload_digest, null: false
      t.integer :work_item_lock_version, null: false
      t.text :destination_url
      t.string :status, null: false, default: "pending_approval"
      t.boolean :dry_run, null: false, default: false
      t.string :prepared_by, null: false
      t.string :approved_by
      t.datetime :approved_at
      t.string :idempotency_key, null: false
      t.json :response, null: false, default: {}
      t.text :error
      t.datetime :delivery_started_at
      t.datetime :delivered_at
      t.datetime :finished_at
      t.string :reconciled_by
      t.datetime :reconciled_at
      t.text :reconciliation_note
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :work_item_handoffs, :idempotency_key, unique: true
    add_index :work_item_handoffs, [ :work_item_id, :status ]
    add_index :work_item_handoffs, :work_item_id, unique: true,
      where: "status IN ('pending_approval', 'approved', 'delivering', 'unknown')",
      name: "index_work_item_handoffs_on_active_work_item"
  end
end
