require "test_helper"

class CallStateTest < ActiveSupport::TestCase
  test "requires call id and statuses" do
    call_state = CallState.new(
      conversation: conversations(:one),
      call_id: nil,
      status: nil,
      review_status: nil
    )

    assert_not call_state.valid?
    assert_includes call_state.errors[:call_id], "can't be blank"
    assert_includes call_state.errors[:status], "can't be blank"
    assert_includes call_state.errors[:review_status], "can't be blank"
  end

  test "ensure for conversation creates default Athena ideation state" do
    conversation = conversations(:two)

    call_state = CallState.ensure_for_conversation(
      conversation,
      provider: "openai_realtime",
      call_id: "CA-new-state",
      status: "active"
    )

    assert_equal "CA-new-state", call_state.call_id
    assert_equal "openai_realtime", call_state.provider
    assert_equal "rev-cycle-ideation-session", call_state.use_case_slug
    assert_equal "active", call_state.status
    assert_equal "draft_only_external_actions", call_state.state["active_constraints"].first
    assert_equal conversation.customer.phone_number, call_state.state.dig("caller", "phone")
  end
end
