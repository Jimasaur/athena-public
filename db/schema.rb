# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_20_000200) do
  create_table "action_drafts", force: :cascade do |t|
    t.boolean "approval_required", default: true, null: false
    t.datetime "approved_at"
    t.string "approved_by"
    t.integer "call_state_id", null: false
    t.json "content", default: {}
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "created_by", null: false
    t.json "external_side_effect", default: {}
    t.string "kind", null: false
    t.json "recipient", default: {}
    t.string "status", default: "pending_approval", null: false
    t.datetime "updated_at", null: false
    t.index ["call_state_id"], name: "index_action_drafts_on_call_state_id"
    t.index ["conversation_id"], name: "index_action_drafts_on_conversation_id"
    t.index ["created_by"], name: "index_action_drafts_on_created_by"
    t.index ["kind"], name: "index_action_drafts_on_kind"
    t.index ["status"], name: "index_action_drafts_on_status"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_settings", force: :cascade do |t|
    t.string "agent_id", null: false
    t.datetime "created_at", null: false
    t.json "data", default: {}
    t.text "first_message"
    t.string "name"
    t.text "system_prompt"
    t.string "tool_url"
    t.json "tools", default: []
    t.string "twilio_number"
    t.datetime "updated_at", null: false
    t.string "voice_id"
    t.index ["agent_id"], name: "index_agent_settings_on_agent_id", unique: true
    t.index ["twilio_number"], name: "index_agent_settings_on_twilio_number"
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "call_events", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.json "data", default: {}
    t.string "direction"
    t.string "from_number"
    t.string "recording_url"
    t.string "status", null: false
    t.string "to_number"
    t.text "transcription"
    t.string "twilio_call_sid", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_call_events_on_conversation_id"
    t.index ["status"], name: "index_call_events_on_status"
    t.index ["twilio_call_sid"], name: "index_call_events_on_twilio_call_sid"
  end

  create_table "call_states", force: :cascade do |t|
    t.string "call_id", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "provider"
    t.string "review_status", default: "pending", null: false
    t.string "space"
    t.json "state", default: {}
    t.string "status", default: "initializing", null: false
    t.datetime "updated_at", null: false
    t.string "use_case_slug"
    t.index ["call_id"], name: "index_call_states_on_call_id", unique: true
    t.index ["conversation_id"], name: "index_call_states_on_conversation_id"
    t.index ["provider"], name: "index_call_states_on_provider"
    t.index ["review_status"], name: "index_call_states_on_review_status"
    t.index ["use_case_slug"], name: "index_call_states_on_use_case_slug"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "agent_name"
    t.datetime "call_started_at"
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "status", default: "open", null: false
    t.text "summary"
    t.integer "transcript_call_event_id"
    t.string "twilio_call_sid"
    t.datetime "updated_at", null: false
    t.index ["channel"], name: "index_conversations_on_channel"
    t.index ["customer_id"], name: "index_conversations_on_customer_id"
    t.index ["status"], name: "index_conversations_on_status"
    t.index ["transcript_call_event_id"], name: "index_conversations_on_transcript_call_event_id"
    t.index ["twilio_call_sid"], name: "index_conversations_on_twilio_call_sid"
  end

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "customer_portrait"
    t.string "greeting_name"
    t.json "metadata", default: {}
    t.string "name"
    t.string "phone_number", null: false
    t.datetime "updated_at", null: false
    t.index ["phone_number"], name: "index_customers_on_phone_number"
  end

  create_table "idea_captures", force: :cascade do |t|
    t.string "category"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "department"
    t.text "impact"
    t.text "next_step"
    t.json "payload", default: {}
    t.text "problem"
    t.text "proposed_solution"
    t.string "status", default: "captured", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_idea_captures_on_category"
    t.index ["conversation_id"], name: "index_idea_captures_on_conversation_id"
    t.index ["status"], name: "index_idea_captures_on_status"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.datetime "sent_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["sent_at"], name: "index_messages_on_sent_at"
  end

  create_table "sidecar_events", force: :cascade do |t|
    t.integer "call_state_id", null: false
    t.boolean "changes_call_behavior", default: false, null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.json "evidence", default: {}
    t.string "kind", null: false
    t.datetime "occurred_at", null: false
    t.json "payload", default: {}
    t.string "provider"
    t.boolean "requires_review", default: false, null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["call_state_id"], name: "index_sidecar_events_on_call_state_id"
    t.index ["conversation_id"], name: "index_sidecar_events_on_conversation_id"
    t.index ["kind"], name: "index_sidecar_events_on_kind"
    t.index ["occurred_at"], name: "index_sidecar_events_on_occurred_at"
    t.index ["source"], name: "index_sidecar_events_on_source"
  end

  create_table "work_item_events", force: :cascade do |t|
    t.integer "work_item_id", null: false
    t.string "event_type", limit: 80, null: false
    t.string "actor", limit: 120, null: false
    t.json "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["work_item_id", "created_at", "id"], name: "index_work_item_events_on_work_item_id_and_created_at_and_id"
  end

  create_table "work_item_handoffs", force: :cascade do |t|
    t.integer "work_item_id", null: false
    t.json "payload", default: {}, null: false
    t.string "payload_digest", null: false
    t.integer "work_item_lock_version", null: false
    t.text "destination_url"
    t.string "status", default: "pending_approval", null: false
    t.boolean "dry_run", default: false, null: false
    t.string "prepared_by", null: false
    t.string "approved_by"
    t.datetime "approved_at"
    t.string "idempotency_key", null: false
    t.json "response", default: {}, null: false
    t.text "error"
    t.datetime "delivery_started_at"
    t.datetime "delivered_at"
    t.datetime "finished_at"
    t.string "reconciled_by"
    t.datetime "reconciled_at"
    t.text "reconciliation_note"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_work_item_handoffs_on_idempotency_key", unique: true
    t.index ["work_item_id", "status"], name: "index_work_item_handoffs_on_work_item_id_and_status"
    t.index ["work_item_id"], name: "index_work_item_handoffs_on_active_work_item", unique: true, where: "status IN ('pending_approval', 'approved', 'delivering', 'unknown')"
    t.index ["work_item_id"], name: "index_work_item_handoffs_on_work_item_id"
  end

  create_table "work_items", force: :cascade do |t|
    t.integer "conversation_id"
    t.integer "idea_capture_id"
    t.string "title", limit: 200, null: false
    t.string "kind", default: "request", null: false
    t.text "description"
    t.text "next_step"
    t.string "owner", limit: 120
    t.string "priority", default: "normal", null: false
    t.string "status", default: "needs_review", null: false
    t.date "due_on"
    t.text "resolution_note"
    t.datetime "resolved_at"
    t.string "intake_source", default: "manual", null: false
    t.boolean "demo", default: false, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_work_items_on_conversation_id"
    t.index ["due_on"], name: "index_work_items_on_due_on"
    t.index ["idea_capture_id"], name: "index_work_items_on_idea_capture_id", unique: true
    t.index ["owner"], name: "index_work_items_on_owner"
    t.index ["status", "priority", "due_on"], name: "index_work_items_on_status_and_priority_and_due_on"
    t.check_constraint "intake_source IN ('voice', 'web', 'manual')", name: "work_items_valid_intake_source"
    t.check_constraint "kind IN ('request', 'issue', 'opportunity', 'follow_up')", name: "work_items_valid_kind"
    t.check_constraint "priority IN ('low', 'normal', 'high', 'urgent')", name: "work_items_valid_priority"
    t.check_constraint "status IN ('needs_review', 'ready', 'in_progress', 'waiting', 'resolved', 'archived')", name: "work_items_valid_status"
  end

  add_foreign_key "action_drafts", "call_states"
  add_foreign_key "action_drafts", "conversations"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "call_events", "conversations"
  add_foreign_key "call_states", "conversations"
  add_foreign_key "conversations", "call_events", column: "transcript_call_event_id"
  add_foreign_key "conversations", "customers"
  add_foreign_key "idea_captures", "conversations"
  add_foreign_key "messages", "conversations"
  add_foreign_key "sidecar_events", "call_states"
  add_foreign_key "sidecar_events", "conversations"
  add_foreign_key "work_item_events", "work_items", on_delete: :cascade
  add_foreign_key "work_item_handoffs", "work_items"
  add_foreign_key "work_items", "conversations", on_delete: :nullify
  add_foreign_key "work_items", "idea_captures", on_delete: :nullify
end
