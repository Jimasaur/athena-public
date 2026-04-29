require "test_helper"

class CallEventTest < ActiveSupport::TestCase
  test "requires call sid and status" do
    call_event = CallEvent.new(conversation: conversations(:one))

    assert_not call_event.valid?
    assert_includes call_event.errors[:twilio_call_sid], "can't be blank"
    assert_includes call_event.errors[:status], "can't be blank"
  end
end
