require "test_helper"

class ConversationReviewStateTest < ActiveSupport::TestCase
  test "marks conversations with pending drafts as needing review" do
    state = ConversationReviewState.new(conversations(:one)).to_h

    assert_equal :needs_review, state[:key]
    assert_equal "Needs review", state[:label]
    assert_includes state[:next_action], "Approve or reject"
  end
end
