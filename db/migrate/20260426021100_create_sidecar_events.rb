class CreateSidecarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :sidecar_events do |t|
      t.references :call_state, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.string :source, null: false
      t.string :kind, null: false
      t.string :provider
      t.json :payload, default: {}
      t.json :evidence, default: {}
      t.boolean :changes_call_behavior, null: false, default: false
      t.boolean :requires_review, null: false, default: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :sidecar_events, :kind
    add_index :sidecar_events, :source
    add_index :sidecar_events, :occurred_at
  end
end
