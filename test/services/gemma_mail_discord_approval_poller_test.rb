require "test_helper"

class GemmaMailDiscordApprovalPollerTest < ActiveSupport::TestCase
  FakeRunner = Struct.new(:responses, :calls, keyword_init: true) do
    def call(*args)
      calls << args
      responses.shift || GemmaMailDiscordApprovalPoller::CommandResult.new(stdout: "", stderr: "unexpected command", exitstatus: 1)
    end
  end

  setup do
    AppSetting.find_or_create_by!(key: "ATHENA_APPROVAL_DISCORD_APPROVER_IDS").update!(value: "approver-1")
  end

  test "sends a Athena approval after a Discord affirmative reply" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000),
          human_message("proceed", timestamp_ms: 1200, id: "reply-1")
        ])),
        command_result("Sent."),
        command_result({ ok: true }.to_json)
      ]
    )

    assert_difference "SidecarEvent.where(kind: 'email_approval.sent').count", 1 do
      result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call
      assert result[:ok]
      assert_equal [ { approval_id: approval_id, action: "send", ok: true } ], result[:processed]
    end

    send_call = runner.calls.find { |args| args.first == "gemma-mail-gog" }
    assert_includes send_call, "send"
    assert_includes send_call, "--confirmed"
    assert_includes send_call, "demo@example.com"

    event = SidecarEvent.where(kind: "email_approval.sent").order(:created_at).last
    assert_equal approval_id, event.payload["approval_id"]
    assert_equal "reply-1", event.payload["discord_response_message_id"]
    assert_equal "proceed", event.payload["discord_response"]
  end

  test "sends transcript approval with suffixed conversation approval id" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}-transcript"
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000),
          human_message("yes", timestamp_ms: 1200, id: "reply-1")
        ])),
        command_result("Sent transcript."),
        command_result({ ok: true }.to_json)
      ]
    )

    assert_difference "SidecarEvent.where(kind: 'email_approval.sent').count", 1 do
      result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call
      assert result[:ok]
      assert_equal [ { approval_id: approval_id, action: "send", ok: true } ], result[:processed]
    end

    event = SidecarEvent.where(kind: "email_approval.sent").order(:created_at).last
    assert_equal approval_id, event.payload["approval_id"]
    assert_equal conversation, event.conversation
  end

  test "does not send an approval twice" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    call_state = CallState.ensure_for_conversation(conversation, provider: "openai_realtime")
    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "test",
      kind: "email_approval.sent",
      provider: "gemma-mail-gog",
      payload: { approval_id: approval_id },
      occurred_at: Time.current
    )
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000),
          human_message("yes", timestamp_ms: 1200, id: "reply-1")
        ]))
      ]
    )

    result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call

    assert result[:ok]
    assert_empty result[:processed]
    assert_nil runner.calls.find { |args| args.first == "gemma-mail-gog" }
  end

  test "ignores non-allowlisted approver" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000),
          human_message("yes", timestamp_ms: 1200, id: "reply-1", author_id: "intruder")
        ]))
      ]
    )

    result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call

    assert result[:ok]
    assert_empty result[:processed]
    assert_nil runner.calls.find { |args| args.first == "gemma-mail-gog" }
  end

  test "blank approver allowlist fails closed" do
    AppSetting.find_by!(key: "ATHENA_APPROVAL_DISCORD_APPROVER_IDS").update!(value: "")
    runner = FakeRunner.new(calls: [], responses: [])

    result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call

    assert_equal false, result[:ok]
    assert_includes result[:error], "ATHENA_APPROVAL_DISCORD_APPROVER_IDS"
    assert_empty runner.calls
  end

  test "records cancellation without sending" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000),
          human_message("cancel", timestamp_ms: 1200, id: "reply-1")
        ])),
        command_result({ ok: true }.to_json)
      ]
    )

    assert_difference "SidecarEvent.where(kind: 'email_approval.cancelled').count", 1 do
      result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call
      assert result[:ok]
      assert_equal "cancel", result[:processed].first[:action]
    end

    assert_nil runner.calls.find { |args| args.first == "gemma-mail-gog" }
  end

  test "applies inline subject edit and reposts approval" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000),
          human_message("edit subject to say OC Update_Plan", timestamp_ms: 1200, id: "reply-1")
        ])),
        command_result({ payload: { id: "updated-approval" } }.to_json),
        command_result({ ok: true }.to_json)
      ]
    )

    assert_difference "SidecarEvent.where(kind: 'email_approval.edited').count", 1 do
      result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call
      assert result[:ok]
      assert_equal "edit", result[:processed].first[:action]
      assert_equal "OC Update_Plan", result[:processed].first[:edits][:subject]
    end

    updated_message_call = runner.calls.find do |args|
      args.first == "openclaw" && args.include?("--message") &&
        args[args.index("--message") + 1].include?("OC Update_Plan")
    end
    assert updated_message_call

    event = SidecarEvent.where(kind: "email_approval.edited").order(:created_at).last
    assert_equal approval_id, event.payload["approval_id"]
    assert_equal "OC Update_Plan", event.payload["subject"]
  end

  test "applies subject edit written with colon shorthand" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000, subject: "Test Number Five"),
          human_message("edit subject: Test #5", timestamp_ms: 1200, id: "reply-1")
        ])),
        command_result({ payload: { id: "updated-approval" } }.to_json),
        command_result({ ok: true }.to_json)
      ]
    )

    result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call

    assert result[:ok]
    assert_equal "edit", result[:processed].first[:action]
    assert_equal "Test #5", result[:processed].first[:edits][:subject]

    event = SidecarEvent.where(kind: "email_approval.edited").order(:created_at).last
    assert_equal "Test #5", event.payload["subject"]
  end

  test "applies subject edit provided after edit clarification prompt" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000, subject: "Test Number Five"),
          human_message("edit", timestamp_ms: 1200, id: "reply-1"),
          bot_message("Athena approval #{approval_id}: what should I change?", timestamp_ms: 1300),
          human_message("subject should be: Test # 5", timestamp_ms: 1400, id: "reply-2", reply_to: "bot-reply")
        ])),
        command_result({ ok: true }.to_json),
        command_result({ payload: { id: "updated-approval" } }.to_json),
        command_result({ ok: true }.to_json)
      ]
    )

    result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call

    assert result[:ok]
    assert_equal 2, result[:processed].length
    assert_equal "edit", result[:processed].last[:action]
    assert_equal "Test # 5", result[:processed].last[:edits][:subject]

    event = SidecarEvent.where(kind: "email_approval.edited").order(:created_at).last
    assert_equal "reply-2", event.payload["discord_response_message_id"]
    assert_equal "Test # 5", event.payload["subject"]
  end

  test "applies subject remove edit against current subject" do
    conversation = conversations(:one)
    approval_id = "athena-conversation-#{conversation.id}"
    call_state = CallState.ensure_for_conversation(conversation, provider: "openai_realtime")
    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "test",
      kind: "email_approval.sent_to_discord",
      provider: "openclaw",
      payload: {
        approval_id: approval_id,
        recipient: "demo@example.com",
        subject: "remove the _ from Update_Plan",
        body: "Stored body"
      },
      occurred_at: Time.current
    )
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([
          approval_message(approval_id, timestamp_ms: 1000, subject: "OC Update_Plan"),
          human_message("edit the subject to remove the _ from Update_Plan", timestamp_ms: 1200, id: "reply-1")
        ])),
        command_result({ payload: { id: "updated-approval" } }.to_json),
        command_result({ ok: true }.to_json)
      ]
    )

    result = GemmaMailDiscordApprovalPoller.new(target: "channel:test", runner: runner).call

    assert result[:ok]
    assert_equal "OC Update Plan", result[:processed].first[:edits][:subject]

    event = SidecarEvent.where(kind: "email_approval.edited").order(:created_at).last
    assert_equal "OC Update Plan", event.payload["subject"]
  end

  test "normalizes legacy OPENCLAW_CLI flag value" do
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([]))
      ]
    )

    GemmaMailDiscordApprovalPoller.new(target: "channel:test", openclaw_cli: "1", runner: runner).call

    assert_equal "openclaw", runner.calls.first.first
  end

  test "reads Athena approval target when configured" do
    AppSetting.create!(key: "ATHENA_APPROVAL_TARGET", value: "channel:athena-approvals")
    runner = FakeRunner.new(
      calls: [],
      responses: [
        command_result(messages_payload([]))
      ]
    )

    GemmaMailDiscordApprovalPoller.new(runner: runner).call

    command = runner.calls.first
    assert_equal "channel:athena-approvals", command[command.index("--target") + 1]
  ensure
    AppSetting.find_by(key: "ATHENA_APPROVAL_TARGET")&.destroy
  end

  private

  def command_result(stdout, stderr: "", exitstatus: 0)
    GemmaMailDiscordApprovalPoller::CommandResult.new(stdout: stdout.to_s, stderr: stderr, exitstatus: exitstatus)
  end

  def messages_payload(messages)
    {
      action: "read",
      payload: {
        ok: true,
        messages: messages.reverse
      }
    }.to_json
  end

  def approval_message(approval_id, timestamp_ms:, subject: "Test subject")
    {
      "id" => "approval-1",
      "timestampMs" => timestamp_ms,
      "content" => <<~TEXT,
        Approval request for the operator:

        Email awaiting your approval:
        - **Approval ID:** #{approval_id}
        - **To:** demo@example.com
        - **Subject:** #{subject}
        - **Body:** Test body

        ATHENA_EMAIL_STATUS: approval_requested
      TEXT
      "author" => { "bot" => true }
    }
  end

  def human_message(content, timestamp_ms:, id:, reply_to: "approval-1", author_id: "approver-1")
    {
      "id" => id,
      "timestampMs" => timestamp_ms,
      "content" => content,
      "replyTo" => reply_to,
      "author" => { "bot" => false, "id" => author_id }
    }
  end

  def bot_message(content, timestamp_ms:, id: "bot-reply")
    {
      "id" => id,
      "timestampMs" => timestamp_ms,
      "content" => content,
      "author" => { "bot" => true }
    }
  end
end
