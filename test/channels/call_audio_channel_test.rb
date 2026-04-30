require "test_helper"

class CallAudioChannelTest < ActionCable::Channel::TestCase
  tests CallAudioChannel

  setup do
    @conversation = conversations(:one)
    @conversation.update!(status: "in_progress")
    stub_connection admin_cable_session: true
  end

  test "rejects raw conversation id without token" do
    subscribe conversation_id: @conversation.id

    assert subscription.rejected?
  end

  test "accepts valid token for in-progress conversation" do
    subscribe conversation_id: @conversation.id, token: LiveAudioAuthorization.token_for(@conversation)

    assert subscription.confirmed?
    assert_has_stream_for @conversation
  end

  test "rejects mismatched token" do
    other = conversations(:two)
    other.update!(status: "in_progress")

    subscribe conversation_id: @conversation.id, token: LiveAudioAuthorization.token_for(other)

    assert subscription.rejected?
  end

  test "rejects completed conversation" do
    @conversation.update!(status: "completed")

    subscribe conversation_id: @conversation.id, token: LiveAudioAuthorization.token_for(@conversation)

    assert subscription.rejected?
  end
end
