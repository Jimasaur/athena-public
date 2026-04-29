require "test_helper"

class GemmaMailDiscordApprovalRequestServiceTest < ActiveSupport::TestCase
  FakeRunner = Struct.new(:calls, :result, keyword_init: true) do
    def call(*args)
      calls << args
      result
    end
  end

  test "posts deterministic Athena approval request to Discord" do
    runner = FakeRunner.new(
      calls: [],
      result: GemmaMailDiscordApprovalRequestService::CommandResult.new(
        stdout: { payload: { id: "discord-message-1" } }.to_json,
        stderr: "",
        exitstatus: 0
      )
    )

    result = GemmaMailDiscordApprovalRequestService.new(
      payload: {
        approval_id: "athena-conversation-123",
        to: "operator@example.com",
        subject: "Hello",
        body: "Body text"
      },
      target: "channel:test",
      runner: runner
    ).call

    assert result[:ok]
    assert_equal "approval_requested", result[:delivery_status]
    assert_equal "discord-message-1", result[:reply]

    command = runner.calls.first
    assert_includes command, "message"
    assert_includes command, "send"
    message = command[command.index("--message") + 1]
    assert_includes message, "Approval ID:** athena-conversation-123"
    assert_includes message, "To:** operator@example.com"
    assert_includes message, "Body preview:** Body text"
    assert_includes message, "yes / approve / send / proceed"
    assert_includes message, "ATHENA_EMAIL_STATUS: approval_requested"
  end

  test "requires configured Discord target" do
    setting = AppSetting.find_by!(key: "GEMMA_MAIL_APPROVAL_TARGET")
    original_value = setting.value
    setting.update!(value: "")

    result =
      begin
        GemmaMailDiscordApprovalRequestService.new(
          payload: {
            to: "operator@example.com",
            subject: "Hello",
            body: "Body text"
          },
          target: "",
          runner: ->(*) { raise "should not run" }
        ).call
      ensure
        setting.update!(value: original_value)
      end

    assert_equal false, result[:ok]
    assert_includes result[:error], "GEMMA_MAIL_APPROVAL_TARGET"
  end

  test "normalizes legacy OPENCLAW_CLI flag value" do
    runner = FakeRunner.new(
      calls: [],
      result: GemmaMailDiscordApprovalRequestService::CommandResult.new(
        stdout: { payload: { id: "discord-message-1" } }.to_json,
        stderr: "",
        exitstatus: 0
      )
    )

    GemmaMailDiscordApprovalRequestService.new(
      payload: {
        approval_id: "athena-conversation-123",
        to: "operator@example.com",
        subject: "Hello",
        body: "Body text"
      },
      target: "channel:test",
      openclaw_cli: "1",
      runner: runner
    ).call

    assert_equal "openclaw", runner.calls.first.first
  end

  test "prefers Athena approval target when configured" do
    AppSetting.create!(key: "ATHENA_APPROVAL_TARGET", value: "channel:athena-approvals")
    runner = FakeRunner.new(
      calls: [],
      result: GemmaMailDiscordApprovalRequestService::CommandResult.new(
        stdout: { payload: { id: "discord-message-1" } }.to_json,
        stderr: "",
        exitstatus: 0
      )
    )

    GemmaMailDiscordApprovalRequestService.new(
      payload: {
        approval_id: "athena-conversation-123",
        to: "operator@example.com",
        subject: "Hello",
        body: "Body text"
      },
      runner: runner
    ).call

    command = runner.calls.first
    assert_equal "channel:athena-approvals", command[command.index("--target") + 1]
  ensure
    AppSetting.find_by(key: "ATHENA_APPROVAL_TARGET")&.destroy
  end
end
