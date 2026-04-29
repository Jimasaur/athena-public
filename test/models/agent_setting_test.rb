require "test_helper"

class AgentSettingTest < ActiveSupport::TestCase
  test "requires agent id" do
    agent_setting = AgentSetting.new

    assert_not agent_setting.valid?
    assert_includes agent_setting.errors[:agent_id], "can't be blank"
  end
end
