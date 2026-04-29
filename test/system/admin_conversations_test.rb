require "application_system_test_case"

class AdminConversationsTest < ApplicationSystemTestCase
  test "view conversations list" do
    visit admin_conversations_path

    assert_text "Conversations"
    assert_text conversations(:one).summary
  end

  test "view conversation detail" do
    conversation = conversations(:one)

    visit admin_conversation_path(conversation)

    assert_text "Transcript"
    assert_text conversation.customer.phone_number
  end
end
