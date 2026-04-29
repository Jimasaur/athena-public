require "test_helper"

module Admin
  class ConversationsControllerTest < ActionDispatch::IntegrationTest
    test "show renders call state sidecar events and action drafts" do
      conversation = conversations(:one)

      get admin_conversation_path(conversation)

      assert_response :success
      assert_select "h2", text: "Needs review"
      assert_select "h2", text: "Call state"
      assert_select "h2", text: "Timeline"
      assert_select "h2", text: "Drafts"
      assert_select "h2", text: "Sidecar events"
      assert_select "h2", text: "Recording unavailable"
      assert_includes @response.body, "Call state created"
      assert_includes @response.body, "Sidecar summary created"
      assert_includes @response.body, "summary.created"
      assert_includes @response.body, "Thanks for the call"
    end

    test "index filters conversations by review state" do
      get admin_conversations_path(review: "needs_review")

      assert_response :success
      assert_includes @response.body, "Needs review"
      assert_includes @response.body, conversations(:one).summary
      assert_select "a[href='#{admin_conversation_path(conversations(:one))}']"
    end

    test "show normalizes provider transcript speaker labels" do
      conversation = conversations(:one)
      call_event = conversation.call_events.create!(
        twilio_call_sid: "CA-transcript-speakers",
        status: "post_call_transcription",
        direction: "inbound",
        from_number: conversation.customer.phone_number,
        data: {
          "type" => "post_call_transcription",
          "data" => {
            "transcript" => [
              { "speaker" => "agent", "message" => "How can I help?" },
              { "speaker" => "caller", "message" => "I need a follow-up." }
            ]
          }
        }
      )
      conversation.update!(transcript_call_event: call_event)

      get admin_conversation_path(conversation)

      assert_response :success
      assert_includes @response.body, '"role":"assistant"'
      assert_includes @response.body, '"role":"user"'
    end
  end
end
