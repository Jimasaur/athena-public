require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "requires channel" do
    conversation = Conversation.new(customer: customers(:one))

    assert_not conversation.valid?
    assert_includes conversation.errors[:channel], "can't be blank"
  end
end
