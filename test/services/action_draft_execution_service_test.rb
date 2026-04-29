require "test_helper"

class ActionDraftExecutionServiceTest < ActiveSupport::TestCase
  test "sends approved follow up draft by Twilio SMS" do
    draft = action_drafts(:one)
    draft.approve!(approved_by: "operator")

    fake_messages = Class.new do
      attr_reader :last_params

      def create(params)
        @last_params = params
        Struct.new(:sid).new("SM123")
      end
    end.new
    fake_client = Struct.new(:messages).new(fake_messages)

    original_new = Twilio::REST::Client.method(:new)
    Twilio::REST::Client.define_singleton_method(:new) { |_sid, _token| fake_client }

    begin
      assert_difference -> { SidecarEvent.count }, 1 do
        result = ActionDraftExecutionService.new(action_draft: draft, executor: "operator").call
        assert result.ok
      end
    ensure
      Twilio::REST::Client.define_singleton_method(:new) do |*args, &block|
        original_new.call(*args, &block)
      end
    end

    assert_equal "+14155551234", fake_messages.last_params[:from]
    assert_equal "+14155550100", fake_messages.last_params[:to]
    assert_includes fake_messages.last_params[:body], "Thanks for the call"

    draft.reload
    assert_equal "executed", draft.status
    assert_equal true, draft.external_side_effect["executed"]
    assert_equal "SM123", draft.external_side_effect["external_id"]

    event = draft.conversation.sidecar_events.order(:created_at).last
    assert_equal "external_action.executed", event.kind
    assert_equal "twilio_sms_executor", event.source
    assert_equal "SM123", event.payload["twilio_message_sid"]
  end

  test "does not send unapproved draft" do
    draft = action_drafts(:one)

    assert_no_difference -> { SidecarEvent.count } do
      result = ActionDraftExecutionService.new(action_draft: draft).call
      assert_not result.ok
      assert_equal "Draft must be approved before it can be executed.", result.error
    end

    assert_equal "pending_approval", draft.reload.status
  end

  test "sends approved email draft through Gemma Mail" do
    draft = email_draft
    draft.approve!(approved_by: "operator")

    captured = nil
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        session_id: "athena-gemma-mail",
        mode: "send",
        action: "gmail_send",
        delivery_status: "sent",
        reply: "Sent the email."
      }
    )

    original_new = GemmaMailAgentService.method(:new)
    GemmaMailAgentService.define_singleton_method(:new) do |**kwargs|
      captured = kwargs
      fake_service
    end

    begin
      assert_difference -> { SidecarEvent.count }, 1 do
        result = ActionDraftExecutionService.new(action_draft: draft, executor: "operator").call
        assert result.ok
      end
    ensure
      GemmaMailAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert_equal "test@example.com", captured[:payload][:to]
    assert_equal "Hello", captured[:payload][:subject]
    assert_equal "Thanks for the call.", captured[:payload][:body]
    assert_equal "send", captured[:payload][:mode]
    assert_equal true, captured[:payload][:send]

    draft.reload
    assert_equal "executed", draft.status
    assert_equal true, draft.external_side_effect["executed"]
    assert_equal "gemma_mail", draft.external_side_effect["provider"]
    assert_equal "sent", draft.external_side_effect["delivery_status"]

    event = draft.conversation.sidecar_events.order(:created_at).last
    assert_equal "external_action.executed", event.kind
    assert_equal "gemma_mail_executor", event.source
    assert_equal "gemma_mail", event.provider
    assert_equal "test@example.com", event.payload["to"]
  end

  test "does not mark email executed without Gemma Mail send confirmation" do
    draft = email_draft
    draft.approve!(approved_by: "operator")

    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        mode: "send",
        action: "gmail_draft",
        delivery_status: "not_sent",
        reply: "I could not send it, but I prepared a draft."
      }
    )

    original_new = GemmaMailAgentService.method(:new)
    GemmaMailAgentService.define_singleton_method(:new) { |**_kwargs| fake_service }

    begin
      assert_difference -> { SidecarEvent.count }, 1 do
        result = ActionDraftExecutionService.new(action_draft: draft).call
        assert_not result.ok
        assert_includes result.error, "did not confirm"
      end
    ensure
      GemmaMailAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    draft.reload
    assert_equal "execution_failed", draft.status
    assert_equal false, draft.external_side_effect["executed"]

    event = draft.conversation.sidecar_events.order(:created_at).last
    assert_equal "external_action.failed", event.kind
    assert event.requires_review?
  end

  test "executes demo drafts without sending Twilio SMS" do
    draft = action_drafts(:one)
    draft.approve!(approved_by: "operator")
    draft.update!(
      external_side_effect: draft.external_side_effect.merge(
        "mode" => "demo",
        "dry_run" => true
      )
    )

    assert_difference -> { SidecarEvent.count }, 1 do
      result = ActionDraftExecutionService.new(action_draft: draft, executor: "operator").call
      assert result.ok
    end

    draft.reload
    assert_equal "executed", draft.status
    assert_equal true, draft.external_side_effect["executed"]
    assert_equal "demo_twilio", draft.external_side_effect["provider"]
    assert_match(/\ASM-DEMO-/, draft.external_side_effect["external_id"])

    event = draft.conversation.sidecar_events.order(:created_at).last
    assert_equal "external_action.executed", event.kind
    assert_equal true, event.payload["dry_run"]
  end

  test "records failed execution when twilio credentials are missing" do
    draft = action_drafts(:one)
    draft.approve!(approved_by: "operator")
    AppSetting.find_by!(key: "TWILIO_ACCOUNT_SID").update!(value: "")

    assert_difference -> { SidecarEvent.count }, 1 do
      result = ActionDraftExecutionService.new(action_draft: draft).call
      assert_not result.ok
      assert_equal "Missing TWILIO_ACCOUNT_SID or TWILIO_AUTH_TOKEN.", result.error
    end

    draft.reload
    assert_equal "execution_failed", draft.status
    assert_equal false, draft.external_side_effect["executed"]
    assert_equal "Missing TWILIO_ACCOUNT_SID or TWILIO_AUTH_TOKEN.", draft.external_side_effect["error"]

    event = draft.conversation.sidecar_events.order(:created_at).last
    assert_equal "external_action.failed", event.kind
    assert event.requires_review?
  end

  test "uses Twilio messaging service when configured" do
    draft = action_drafts(:one)
    draft.approve!(approved_by: "operator")
    AppSetting.create!(key: "TWILIO_MESSAGING_SERVICE_SID", value: "MG123")

    fake_messages = Class.new do
      attr_reader :last_params

      def create(params)
        @last_params = params
        Struct.new(:sid).new("SM123")
      end
    end.new
    fake_client = Struct.new(:messages).new(fake_messages)

    original_new = Twilio::REST::Client.method(:new)
    Twilio::REST::Client.define_singleton_method(:new) { |_sid, _token| fake_client }

    begin
      result = ActionDraftExecutionService.new(action_draft: draft, executor: "operator").call
      assert result.ok
    ensure
      Twilio::REST::Client.define_singleton_method(:new) do |*args, &block|
        original_new.call(*args, &block)
      end
    end

    assert_equal "MG123", fake_messages.last_params[:messaging_service_sid]
    assert_nil fake_messages.last_params[:from]
    assert_equal "+14155550100", fake_messages.last_params[:to]
    assert_equal "MG123", draft.reload.external_side_effect["provider"].present? && draft.conversation.sidecar_events.order(:created_at).last.payload["messaging_service_sid"]
  end

  test "does not send when recipient opted out" do
    draft = action_drafts(:one)
    draft.conversation.customer.update!(metadata: { "sms_opt_out" => true })
    draft.approve!(approved_by: "operator")

    assert_difference -> { SidecarEvent.count }, 1 do
      result = ActionDraftExecutionService.new(action_draft: draft).call
      assert_not result.ok
      assert_equal "Recipient is marked do-not-contact or opted out of SMS.", result.error
    end

    assert_equal "execution_failed", draft.reload.status
  end

  private

  def email_draft
    call_states(:one).action_drafts.create!(
      conversation: conversations(:one),
      kind: "email",
      status: ActionDraft::PENDING_APPROVAL_STATUS,
      created_by: "agent_tool",
      approval_required: true,
      recipient: { email: "test@example.com" },
      content: {
        subject: "Hello",
        body: "Thanks for the call."
      },
      external_side_effect: {
        type: "send_email",
        executed: false
      }
    )
  end
end
