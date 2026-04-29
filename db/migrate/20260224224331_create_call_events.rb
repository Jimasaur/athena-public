class CreateCallEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :call_events do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :twilio_call_sid, null: false
      t.string :status, null: false
      t.string :direction
      t.string :from_number
      t.string :to_number
      t.string :recording_url
      t.text :transcription
      t.json :data, default: {}

      t.timestamps
    end

    add_index :call_events, :twilio_call_sid
    add_index :call_events, :status
  end
end
