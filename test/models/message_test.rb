require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "requires role, content, and sent_at" do
    message = Message.new(conversation: conversations(:one))

    assert_not message.valid?
    assert_includes message.errors[:role], "can't be blank"
    assert_includes message.errors[:content], "can't be blank"
    assert_includes message.errors[:sent_at], "can't be blank"
  end
end
