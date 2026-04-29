namespace :data do
  desc "Reset conversations, call events, messages, and customers"
  task reset_conversations: :environment do
    Conversation.update_all(transcript_call_event_id: nil)

    messages = Message.delete_all
    call_events = CallEvent.delete_all
    conversations = Conversation.delete_all
    customers = Customer.delete_all

    puts "Deleted: conversations=#{conversations}, call_events=#{call_events}, messages=#{messages}, customers=#{customers}"
  end
end
