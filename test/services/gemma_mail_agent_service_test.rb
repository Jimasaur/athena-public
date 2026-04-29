require "test_helper"

class GemmaMailAgentServiceTest < ActiveSupport::TestCase
  test "routes email draft requests to gemma mail openclaw agent" do
    captured = nil
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        session_id: "athena-gemma-mail",
        reply: "Subject: Hello\n\nBody: Drafted for review."
      }
    )

    original_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) do |params|
      captured = params
      fake_service
    end

    begin
      result = GemmaMailAgentService.new(
        payload: {
          to: "test@example.com",
          subject: "Hello",
          context: "Thank them for the call."
        }
      ).call
    ensure
      OpenClawAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert result[:ok]
    assert_equal "mail", captured[:agent]
    assert_equal "gemma4", captured[:profile]
    assert_equal "athena-gemma-mail", captured[:session_id]
    assert_includes captured[:prompt], "Requested mode: draft"
    assert_includes captured[:prompt], "to: test@example.com"
    assert_equal "gmail_draft", result[:action]
    assert_equal "draft", result[:mode]
    assert_equal "draft", result[:delivery_status]
    assert_includes result[:reply], "Subject: Hello"
  end

  test "marks explicit send requests as send mode" do
    original_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) do |_params|
      Struct.new(:call).new(
        {
          ok: true,
          provider: "openclaw",
          agent: "mail",
          session_id: "athena-gemma-mail",
          reply: "Sent the email."
        }
      )
    end

    begin
      result = GemmaMailAgentService.new(
        payload: {
          to: "test@example.com",
          subject: "Hello",
          body: "Thanks.",
          send: true
        }
      ).call
    ensure
      OpenClawAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert_equal "send", result[:mode]
    assert_equal "gmail_send", result[:action]
    assert_equal "sent", result[:delivery_status]
  end

  test "approval mode delivers Gemma Mail request to Discord" do
    captured = nil
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        channel: "discord",
        reply_to: "channel:fixture-channel",
        reply: "I posted the approval request.\nATHENA_EMAIL_STATUS: approval_requested"
      }
    )

    original_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) do |params|
      captured = params
      fake_service
    end

    begin
      result = GemmaMailAgentService.new(
        payload: {
          to: "test@example.com",
          subject: "Hello",
          body: "Thanks.",
          mode: "approval",
          approval_workflow: true
        }
      ).call
    ensure
      OpenClawAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert result[:ok]
    assert_equal "mail", captured[:agent]
    assert_equal "gemma4", captured[:profile]
    assert_equal "gemma-mail-discord-session", captured[:session_id]
    assert_equal false, captured[:default_session]
    assert_equal "discord", captured[:channel]
    assert_equal true, captured[:deliver]
    assert_equal "discord", captured[:reply_channel]
    assert_equal "channel:fixture-channel", captured[:reply_to]
    assert_includes captured[:prompt], "Requested mode: approval"
    assert_includes captured[:prompt], "same Discord channel session"
    assert_equal "approval", result[:mode]
    assert_equal "gmail_approval_requested", result[:action]
    assert_equal "approval_requested", result[:delivery_status]
    assert_includes result[:reply], "approval request"
  end
end
