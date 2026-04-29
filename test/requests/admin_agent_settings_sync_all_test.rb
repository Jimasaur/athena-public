require "test_helper"

class AdminAgentSettingsSyncAllTest < ActionDispatch::IntegrationTest
  test "sync all explains realtime profiles are local" do
    assert_no_difference -> { AgentSetting.count } do
      post sync_all_admin_agent_settings_path
    end

    assert_response :redirect
    assert_equal "OpenAI Realtime profiles are configured locally.", flash[:notice]
  end
end
