require "test_helper"

class SidecarEventTest < ActiveSupport::TestCase
  test "requires source kind and occurred at" do
    event = SidecarEvent.new(call_state: call_states(:one), conversation: conversations(:one))

    assert_not event.valid?
    assert_includes event.errors[:source], "can't be blank"
    assert_includes event.errors[:kind], "can't be blank"
    assert_includes event.errors[:occurred_at], "can't be blank"
  end
end
