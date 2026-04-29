require "test_helper"

class TranscriptRoleNormalizerTest < ActiveSupport::TestCase
  test "normalizes assistant-like role aliases" do
    assert_equal "assistant", TranscriptRoleNormalizer.call("agent")
    assert_equal "assistant", TranscriptRoleNormalizer.call("assistant_response")
    assert_equal "assistant", TranscriptRoleNormalizer.call("outbound_track")
    assert_equal "assistant", TranscriptRoleNormalizer.from_entry({ "speaker" => "voice-agent" })
  end

  test "normalizes user-like role aliases" do
    assert_equal "user", TranscriptRoleNormalizer.call("user")
    assert_equal "user", TranscriptRoleNormalizer.call("caller")
    assert_equal "user", TranscriptRoleNormalizer.call("inbound_track")
    assert_equal "user", TranscriptRoleNormalizer.from_entry({ "participant_type" => "patient" })
  end
end
