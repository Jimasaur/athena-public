require "test_helper"

module Admin
  class ActionDraftsControllerTest < ActionDispatch::IntegrationTest
    test "approve records review event and updates call state" do
      draft = action_drafts(:one)

      assert_difference -> { SidecarEvent.count }, 1 do
        post approve_admin_action_draft_path(draft), params: { reviewer: "james" }
      end

      assert_redirected_to admin_conversation_path(draft.conversation)

      draft.reload
      assert_equal "approved", draft.status
      assert_equal "james", draft.approved_by

      call_state = draft.call_state.reload
      assert_equal "approved", call_state.review_status
      assert_equal "approved", call_state.state["review_status"]

      event = draft.conversation.sidecar_events.order(:created_at).last
      assert_equal "action_draft.approved", event.kind
      assert_equal "human_review", event.source
      assert_equal draft.id, event.payload["action_draft_id"]
      assert_equal "approved", event.payload["status"]
    end

    test "reject records review event and reason" do
      draft = action_drafts(:one)

      assert_difference -> { SidecarEvent.count }, 1 do
        post reject_admin_action_draft_path(draft), params: { reviewer: "james", reason: "Too vague." }
      end

      assert_redirected_to admin_conversation_path(draft.conversation)

      draft.reload
      assert_equal "rejected", draft.status
      assert_equal "james", draft.approved_by
      assert_equal "Too vague.", draft.external_side_effect["rejection_reason"]

      call_state = draft.call_state.reload
      assert_equal "rejected", call_state.review_status

      event = draft.conversation.sidecar_events.order(:created_at).last
      assert_equal "action_draft.rejected", event.kind
      assert_equal "Too vague.", event.payload["reason"]
    end

    test "reviewed drafts cannot be reviewed again" do
      draft = action_drafts(:one)
      draft.approve!(approved_by: "operator")

      assert_no_difference -> { SidecarEvent.count } do
        post reject_admin_action_draft_path(draft), params: { reviewer: "james" }
      end

      assert_redirected_to admin_conversation_path(draft.conversation)
      assert_equal "approved", draft.reload.status
    end

    test "execute sends approved draft" do
      draft = action_drafts(:one)
      draft.approve!(approved_by: "operator")

      fake_messages = Class.new do
        def create(_params)
          Struct.new(:sid).new("SM123")
        end
      end.new
      fake_client = Struct.new(:messages).new(fake_messages)

      original_new = Twilio::REST::Client.method(:new)
      Twilio::REST::Client.define_singleton_method(:new) { |_sid, _token| fake_client }

      begin
        assert_difference -> { SidecarEvent.count }, 1 do
          post execute_admin_action_draft_path(draft), params: { executor: "james" }
        end
      ensure
        Twilio::REST::Client.define_singleton_method(:new) do |*args, &block|
          original_new.call(*args, &block)
        end
      end

      assert_redirected_to admin_conversation_path(draft.conversation)
      assert_equal "executed", draft.reload.status
      assert_equal "Draft sent.", flash[:notice]
    end
  end
end
