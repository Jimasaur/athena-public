class AddTranscriptCallEventToConversations < ActiveRecord::Migration[8.1]
  def change
    add_reference :conversations, :transcript_call_event, foreign_key: { to_table: :call_events }
  end
end
