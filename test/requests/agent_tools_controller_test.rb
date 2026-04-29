require "test_helper"

class AgentToolsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "lookup returns customer by phone" do
    customer = customers(:one)

    post agent_tools_lookup_path, params: { phone_number: customer.phone_number }

    assert_response :success
    assert_equal customer.phone_number, response.parsed_body.dig("customer", "phone_number")
  end

  test "update modifies customer metadata" do
    customer = customers(:one)

    post agent_tools_update_path, params: {
      customer_id: customer.id,
      metadata: { plan: "Enterprise" }
    }

    assert_response :success
    assert_equal "Enterprise", customer.reload.metadata["plan"]
  end

  test "web search returns results from configured service" do
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        query: "Essentia Health",
        provider: "brave_search",
        results: [ { title: "Essentia", url: "https://example.com" } ]
      }
    )

    original_new = WebSearchService.method(:new)
    WebSearchService.define_singleton_method(:new) { |_params| fake_service }

    begin
      post agent_tools_web_search_path, params: { query: "Essentia Health" }
    ensure
      WebSearchService.define_singleton_method(:new) do |*args, &block|
        original_new.call(*args, &block)
      end
    end

    assert_response :success
    assert_equal "brave_search", response.parsed_body["provider"]
    assert_equal "Essentia", response.parsed_body.dig("results", 0, "title")
  end

  test "dispatcher routes realtime web search request as query" do
    captured = []
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        query: "latest global news headlines about Iran",
        provider: "brave_search",
        results: [ { title: "Iran headlines", url: "https://example.com" } ]
      }
    )

    original_new = WebSearchService.method(:new)
    WebSearchService.define_singleton_method(:new) do |**kwargs|
      captured << kwargs
      fake_service
    end

    begin
      post agent_tools_command_path, params: {
        command: "web_search",
        request: "latest global news headlines about Iran"
      }
    ensure
      WebSearchService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert_response :success
    assert_equal "brave_search", response.parsed_body["provider"]
    assert_equal "latest global news headlines about Iran", captured.first[:query]
  end

  test "openclaw chat returns ideation result" do
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "main",
        session_id: "athena-openclaw",
        reply: "Here are three directions to explore next."
      }
    )

    original_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) { |_params| fake_service }

    begin
      post agent_tools_openclaw_chat_path, params: { prompt: "Help me think through this product idea" }
    ensure
      OpenClawAgentService.define_singleton_method(:new) do |*args, &block|
        original_new.call(*args, &block)
      end
    end

    assert_response :success
    assert_equal "openclaw", response.parsed_body["provider"]
    assert_includes response.parsed_body["reply"], "three directions"
  end

  test "status returns app health payload" do
    post agent_tools_status_path

    assert_response :success
    assert_equal true, response.parsed_body["ok"]
    assert_equal "status", response.parsed_body["command"]
    assert_equal "Athena", response.parsed_body.dig("app", "name")
  end

  test "dispatcher routes status command" do
    post agent_tools_command_path, params: { command: "status" }

    assert_response :success
    assert_equal "status", response.parsed_body["command"]
  end

  test "dispatcher routes semantic request to status intent" do
    post agent_tools_command_path, params: { command: "semantic_request", request: "Status" }

    assert_response :success
    assert_equal "status", response.parsed_body["command"]
    assert_equal "Athena", response.parsed_body.dig("app", "name")
  end

  test "capture idea creates retreat idea card and audit events" do
    conversation = conversations(:one)

    assert_difference -> { conversation.idea_captures.count }, 1 do
      assert_difference -> { conversation.sidecar_events.where(kind: "idea_capture.captured").count }, 1 do
        post agent_tools_capture_idea_path, params: {
          conversation_id: conversation.id,
          title: "Prior auth queue automation",
          category: "Prior Authorization",
          problem: "Staff manually check the same queue every morning.",
          proposed_solution: "Flag clean accounts and route them to the right team automatically.",
          impact: "Reduce staff time and prevent delays.",
          next_step: "Validate the trigger fields with a one-week sample."
        }
      end
    end

    assert_response :success
    assert_equal true, response.parsed_body["ok"]
    assert_equal "capture_idea", response.parsed_body["command"]
    assert_equal "idea_captured", response.parsed_body["action"]
    assert_equal "Prior auth queue automation", conversation.idea_captures.order(:created_at).last.title
  end

  test "dispatcher routes semantic summary locally" do
    conversation = conversations(:one)
    conversation.messages.create!(role: "user", content: "Can you recap the intake?", sent_at: Time.current)

    original_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) { |_params| raise "OpenClaw should not be used" }

    begin
      post agent_tools_command_path, params: { command: "semantic_request", request: "Get the summary of the last call." }
    ensure
      OpenClawAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert_response :success
    assert_equal "summarize_last_call", response.parsed_body["command"]
    assert_includes response.parsed_body["reply"], "Most recent user request"
  end

  test "dispatcher routes semantic weather through web search" do
    captured = []
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        query: "current weather White Bear Lake Minnesota",
        provider: "brave_search",
        results: [
          {
            title: "White Bear Lake Weather",
            description: "Current conditions are sunny and 42 degrees."
          }
        ]
      }
    )

    original_web_search_new = WebSearchService.method(:new)
    WebSearchService.define_singleton_method(:new) do |**kwargs|
      captured << kwargs
      fake_service
    end
    original_openclaw_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) { |*_args, **_kwargs| raise "OpenClaw should not handle weather" }

    begin
      post agent_tools_command_path, params: {
        command: "semantic_request",
        request: "What's the weather in White Bear Lake Minnesota today?"
      }
    ensure
      WebSearchService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_web_search_new.call(*args, **kwargs, &block)
      end
      OpenClawAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_openclaw_new.call(*args, **kwargs, &block)
      end
    end

    assert_response :success
    assert_equal "semantic_request", response.parsed_body["command"]
    assert_equal "weather", response.parsed_body["intent"]
    assert_equal "White Bear Lake Minnesota", response.parsed_body["location"]
    assert_equal "brave_search", response.parsed_body["provider"]
    assert_includes response.parsed_body["reply"], "White Bear Lake"
    assert_equal "current weather White Bear Lake Minnesota", captured.first[:query]
    assert_equal 3, captured.first[:max_results]
  end

  test "dispatcher asks for weather location without calling sidecars" do
    original_web_search_new = WebSearchService.method(:new)
    WebSearchService.define_singleton_method(:new) { |_params| raise "Web search should not run without a location" }
    original_openclaw_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) { |_params| raise "OpenClaw should not run without a location" }

    begin
      post agent_tools_command_path, params: {
        command: "semantic_request",
        request: "What's the weather today?"
      }
    ensure
      WebSearchService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_web_search_new.call(*args, **kwargs, &block)
      end
      OpenClawAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_openclaw_new.call(*args, **kwargs, &block)
      end
    end

    assert_response :success
    assert_equal false, response.parsed_body["ok"]
    assert_equal "semantic_request", response.parsed_body["command"]
    assert_includes response.parsed_body["error"], "location"
  end

  test "dispatcher sends semantic email request to Gemma Mail approval handoff" do
    assert_no_difference "ActionDraft.where(kind: 'email').count" do
      assert_difference "SidecarEvent.where(kind: 'email_approval.queued').count", 1 do
        assert_enqueued_with(job: GemmaMailApprovalJob) do
          post agent_tools_command_path, params: {
            command: "semantic_request",
            request: "Send an email to operator@example.com with subject \"Test subject\" and body \"Test body\"."
          }
        end
      end
    end

    assert_response :success
    assert_equal "gmail_send", response.parsed_body["command"]
    assert_equal "gmail_approval_requested", response.parsed_body["action"]
    assert_equal "approval", response.parsed_body["mode"]
    assert_equal "operator@example.com", response.parsed_body["recipient"]
    assert_equal "Test subject", response.parsed_body["subject"]
    assert_includes response.parsed_body["reply"], "Discord approval"
  end

  test "email approval handoff defaults recipient from conversation customer email" do
    customer = customers(:one)
    customer.update!(metadata: customer.metadata.merge("email" => "operator@example.com"))
    conversation = customer.conversations.create!(
      channel: "voice",
      status: "in_progress",
      agent_name: "Athena",
      twilio_call_sid: "CA-default-email"
    )

    assert_difference "conversation.sidecar_events.where(kind: 'email_approval.queued').count", 1 do
      assert_enqueued_with(job: GemmaMailApprovalJob) do
        post agent_tools_command_path, params: {
          command: "semantic_request",
          conversation_id: conversation.id,
          request: "Email me with subject \"Default recipient\" and body \"This should use my saved email.\""
        }
      end
    end

    assert_response :success
    assert_equal "gmail_send", response.parsed_body["command"]
    assert_equal "operator@example.com", response.parsed_body["recipient"]

    event = conversation.sidecar_events.where(kind: "email_approval.queued").order(:created_at).last
    assert_equal "operator@example.com", event.payload["recipient"]
  end

  test "Gemma Mail approval job records Discord handoff result" do
    conversation = conversations(:one)
    call_state = call_states(:one)
    payload = {
      to: "test@example.com",
      subject: "Hello",
      body: "Thanks.",
      request: "Email test@example.com",
      conversation_id: conversation.id,
      approval_channel: "discord",
      approval_target: "channel:athena-approvals",
      mode: "approval",
      approval_workflow: true
    }
    captured_kwargs = []
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        channel: "discord",
        reply_to: "channel:fixture-channel",
        mode: "approval",
        action: "gmail_approval_requested",
        delivery_status: "approval_requested",
        reply: "Posted approval request."
      }
    )

    original_new = GemmaMailDiscordApprovalRequestService.method(:new)
    GemmaMailDiscordApprovalRequestService.define_singleton_method(:new) do |**kwargs|
      captured_kwargs << kwargs
      fake_service
    end

    begin
      assert_difference "SidecarEvent.where(kind: 'email_approval.sent_to_discord').count", 1 do
        GemmaMailApprovalJob.perform_now(call_state.id, payload)
      end
    ensure
      GemmaMailDiscordApprovalRequestService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    event = SidecarEvent.where(kind: "email_approval.sent_to_discord").order(:created_at).last
    assert_equal conversation, event.conversation
    assert_equal "test@example.com", event.payload["recipient"]
    assert_equal "channel:athena-approvals", event.payload["approval_target"]
    assert_equal "approval_requested", event.payload.dig("result", "delivery_status")
    assert_equal "discord", captured_kwargs.first[:channel]
    assert_equal "channel:athena-approvals", captured_kwargs.first[:target]
  end

  test "Gemma Mail approval job schedules retry after transient Discord handoff failure" do
    conversation = conversations(:one)
    call_state = call_states(:one)
    payload = {
      to: "test@example.com",
      subject: "Hello",
      body: "Thanks.",
      request: "Email test@example.com",
      conversation_id: conversation.id,
      approval_id: "athena-conversation-#{conversation.id}",
      approval_channel: "discord",
      approval_target: "channel:athena-approvals",
      mode: "approval",
      approval_workflow: true
    }
    fake_service = Struct.new(:call).new(
      {
        ok: false,
        error: "Discord approval request failed: Error: Missing Access"
      }
    )

    original_new = GemmaMailDiscordApprovalRequestService.method(:new)
    GemmaMailDiscordApprovalRequestService.define_singleton_method(:new) { |**_kwargs| fake_service }

    begin
      assert_enqueued_jobs 1 do
        assert_difference "SidecarEvent.where(kind: 'email_approval.failed').count", 1 do
          assert_difference "SidecarEvent.where(kind: 'email_approval.retry_scheduled').count", 1 do
            GemmaMailApprovalJob.perform_now(call_state.id, payload)
          end
        end
      end
    ensure
      GemmaMailDiscordApprovalRequestService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    retry_event = SidecarEvent.where(kind: "email_approval.retry_scheduled").order(:created_at).last
    assert_equal "channel:athena-approvals", retry_event.payload["approval_target"]
    assert_equal 2, retry_event.payload["approval_delivery_attempt"]
    assert_equal 30, retry_event.payload["wait_seconds"]
  end

  test "explicit draft email command routes directly to Gemma Mail" do
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        session_id: "athena-gemma-mail",
        mode: "draft",
        action: "gmail_draft",
        reply: "Drafted the email for review."
      }
    )

    original_new = GemmaMailAgentService.method(:new)
    GemmaMailAgentService.define_singleton_method(:new) { |_params| fake_service }

    begin
      post agent_tools_command_path, params: {
        command: "email",
        to: "test@example.com",
        subject: "Hello",
        mode: "draft"
      }
    ensure
      GemmaMailAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert_response :success
    assert_equal "gmail_send", response.parsed_body["command"]
    assert_equal "gmail_draft", response.parsed_body["action"]
    assert_equal "Drafted the email for review.", response.parsed_body["reply"]
  end

  test "semantic email draft send request reports draft status without duplicating draft" do
    draft = call_states(:one).action_drafts.create!(
      conversation: conversations(:one),
      kind: "email",
      status: ActionDraft::PENDING_APPROVAL_STATUS,
      created_by: "agent_tool",
      approval_required: true,
      recipient: { email: "test@example.com" },
      content: { subject: "Hello", body: "Thanks." },
      external_side_effect: { type: "send_email", executed: false }
    )

    assert_no_difference "ActionDraft.where(kind: 'email').count" do
      post agent_tools_command_path, params: {
        command: "semantic_request",
        request: "Send the email draft with draft_id #{draft.id} to test@example.com."
      }
    end

    assert_response :success
    assert_equal "gmail_send", response.parsed_body["command"]
    assert_equal "gmail_draft_status", response.parsed_body["action"]
    assert_equal draft.id, response.parsed_body["draft_id"]
    assert_includes response.parsed_body["reply"], "waiting for review"
  end

  test "summarize last call returns recent conversation" do
    customer = customers(:one)
    conversation = customer.conversations.create!(channel: "voice", status: "open", agent_name: "Athena")
    conversation.messages.create!(role: "assistant", content: "Hello from Athena", sent_at: Time.current)

    post agent_tools_summarize_last_call_path

    assert_response :success
    assert_equal conversation.id, response.parsed_body.dig("call", "id")
    contents = response.parsed_body.dig("call", "recent_messages").map { |message| message["content"] }
    assert_includes contents, "Hello from Athena"
  end

  test "find contact returns matching customer by name" do
    customer = customers(:one)

    post agent_tools_find_contact_path, params: { query: customer.name }

    assert_response :success
    assert_equal true, response.parsed_body["found"]
    assert_equal customer.id, response.parsed_body.dig("contacts", 0, "id")
  end

  test "draft follow up returns generated draft" do
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "main",
        session_id: "athena-openclaw",
        reply: "Thanks for the call. Let me know if you'd like to continue next week."
      }
    )

    original_new = OpenClawAgentService.method(:new)
    OpenClawAgentService.define_singleton_method(:new) { |_params| fake_service }

    begin
      post agent_tools_draft_follow_up_path, params: { context: "Follow up after a test call" }
    ensure
      OpenClawAgentService.define_singleton_method(:new) do |*args, &block|
        original_new.call(*args, &block)
      end
    end

    assert_response :success
    assert_equal "draft_follow_up", response.parsed_body["command"]
    assert_includes response.parsed_body["reply"], "Thanks for the call"
  end

  test "athena calls latest returns recent conversations" do
    post agent_tools_athena_calls_latest_path, params: { limit: 1 }

    assert_response :success
    assert_equal 1, response.parsed_body["calls"].length
    assert response.parsed_body["calls"].first["customer"]["name"].present?
  end

  test "calendar availability returns setup error when connector is missing" do
    post agent_tools_calendar_availability_path, params: { start_at: "2026-04-19T10:00:00Z" }

    assert_response :service_unavailable
    assert_includes response.parsed_body["error"], "GOOGLE_CALENDAR_TOOL_URL"
  end

  test "gmail send falls back to gemma mail openclaw agent when connector is missing" do
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        session_id: "athena-gemma-mail",
        mode: "draft",
        action: "gmail_draft",
        reply: "Subject: Hello\n\nBody: Thanks for the call."
      }
    )

    original_new = GemmaMailAgentService.method(:new)
    GemmaMailAgentService.define_singleton_method(:new) { |_params| fake_service }

    begin
      post agent_tools_gmail_send_path, params: { to: "test@example.com", subject: "Hello", mode: "draft" }
    ensure
      GemmaMailAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert_response :success
    assert_equal "gmail_send", response.parsed_body["command"]
    assert_equal "mail", response.parsed_body["agent"]
    assert_equal "draft", response.parsed_body["mode"]
    assert_includes response.parsed_body["reply"], "Subject: Hello"
  end

  test "dispatcher defaults email command to Gemma Mail approval handoff" do
    assert_enqueued_with(job: GemmaMailApprovalJob) do
      post agent_tools_command_path, params: { command: "email", to: "test@example.com", subject: "Hello", body: "Thanks." }
    end

    assert_response :success
    assert_equal "gmail_send", response.parsed_body["command"]
    assert_equal "gmail_approval_requested", response.parsed_body["action"]
    assert_equal "approval", response.parsed_body["mode"]
  end

  test "dispatcher routes explicit draft email command to gemma mail" do
    fake_service = Struct.new(:call).new(
      {
        ok: true,
        provider: "openclaw",
        agent: "mail",
        session_id: "athena-gemma-mail",
        mode: "draft",
        action: "gmail_draft",
        reply: "Drafted the email for review."
      }
    )

    original_new = GemmaMailAgentService.method(:new)
    GemmaMailAgentService.define_singleton_method(:new) { |_params| fake_service }

    begin
      post agent_tools_command_path, params: { command: "email", to: "test@example.com", subject: "Hello", mode: "draft" }
    ensure
      GemmaMailAgentService.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    assert_response :success
    assert_equal "gmail_send", response.parsed_body["command"]
    assert_equal "Drafted the email for review.", response.parsed_body["reply"]
  end
end
