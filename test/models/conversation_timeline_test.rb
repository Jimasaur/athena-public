require "test_helper"

class ConversationTimelineTest < ActiveSupport::TestCase
  test "combines call state call events sidecar events and drafts" do
    conversation = conversations(:one)

    entries = ConversationTimeline.new(conversation).entries

    titles = entries.map(&:title)
    assert_includes titles, "Call state created"
    assert_includes titles, "Call completed"
    assert_includes titles, "Sidecar summary created"
    assert_includes titles, "Draft pending approval"
  end

  test "maps executed sidecar events for demo timeline" do
    conversation = conversations(:one)
    call_state = call_states(:one)
    call_state.sidecar_events.create!(
      conversation: conversation,
      source: "twilio_sms_executor",
      kind: "external_action.executed",
      provider: "twilio",
      payload: { "twilio_message_sid" => "SM123" },
      evidence: { "action_draft_id" => action_drafts(:one).id },
      occurred_at: Time.current
    )

    entry = ConversationTimeline.new(conversation).entries.find { |item| item.title == "External action executed" }

    assert_equal "emerald", entry.tone
    assert_equal "ti-send", entry.icon
    assert_equal "SM123", entry.detail
  end
end
