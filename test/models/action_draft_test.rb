require "test_helper"

class ActionDraftTest < ActiveSupport::TestCase
  test "requires kind status and creator" do
    draft = ActionDraft.new(
      call_state: call_states(:one),
      conversation: conversations(:one),
      status: nil
    )

    assert_not draft.valid?
    assert_includes draft.errors[:kind], "can't be blank"
    assert_includes draft.errors[:status], "can't be blank"
    assert_includes draft.errors[:created_by], "can't be blank"
  end

  test "approving marks draft reviewed without executing the external side effect" do
    draft = action_drafts(:one)

    draft.approve!(approved_by: "operator")

    assert_equal "approved", draft.status
    assert_equal "operator", draft.approved_by
    assert draft.approved_at.present?
    assert_equal true, draft.external_side_effect["approved"]
    assert_equal false, draft.external_side_effect["executed"]
  end

  test "executed drafts store provider external id" do
    draft = action_drafts(:one)

    draft.mark_executed!(provider: "twilio", external_id: "SM123")

    assert_equal "executed", draft.status
    assert_equal "twilio", draft.external_side_effect["provider"]
    assert_equal true, draft.external_side_effect["executed"]
    assert_equal "SM123", draft.external_side_effect["external_id"]
  end

  test "rejecting records reviewer and reason" do
    draft = action_drafts(:one)

    draft.reject!(rejected_by: "operator", reason: "Already handled.")

    assert_equal "rejected", draft.status
    assert_equal "operator", draft.approved_by
    assert_equal false, draft.external_side_effect["approved"]
    assert_equal "Already handled.", draft.external_side_effect["rejection_reason"]
  end
end
