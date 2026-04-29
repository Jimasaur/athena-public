require "test_helper"

module Admin
  class AgentSettingsControllerTest < ActionDispatch::IntegrationTest
    test "index lists agent settings" do
      get admin_agent_settings_path

      assert_response :success
      assert_includes @response.body, "Athena Voice"
      assert_includes @response.body, "agent-001"
    end

    test "create adds a new agent setting" do
      assert_difference -> { AgentSetting.count }, 1 do
        post admin_agent_settings_path, params: {
          agent_setting: {
            agent_id: "agent-003",
            name: "Athena Support",
            system_prompt: "Handle support calls and create tickets.",
            voice_id: "marin",
            tool_url: "https://example.com/agent_tools/lookup",
            tools_json: JSON.generate([ { "name" => "customer_lookup" } ])
          }
        }
      end

      assert_redirected_to admin_agent_setting_path(AgentSetting.order(:created_at).last)
    end

    test "update edits an existing agent setting" do
      agent_setting = agent_settings(:one)

      patch admin_agent_setting_path(agent_setting), params: {
        agent_setting: {
          name: "Athena Voice Updated",
          tools_json: JSON.generate([ { "name" => "customer_lookup" } ])
        }
      }

      assert_redirected_to admin_agent_setting_path(agent_setting)
      assert_equal "Athena Voice Updated", agent_setting.reload.name
    end

    test "destroy removes an agent setting" do
      agent_setting = agent_settings(:two)

      assert_difference -> { AgentSetting.count }, -1 do
        delete admin_agent_setting_path(agent_setting)
      end

      assert_redirected_to admin_agent_settings_path
    end

    test "edit shows imported realtime number when twilio credentials are missing" do
      AppSetting.find_by!(key: "TWILIO_ACCOUNT_SID").update!(value: "")
      AppSetting.find_by!(key: "TWILIO_AUTH_TOKEN").update!(value: "")
      AppSetting.create!(key: "VOICEBOT_TWILIO_FROM_NUMBER", value: "+14155559876")

      get edit_admin_agent_setting_path(agent_settings(:one))

      assert_response :success
      assert_includes @response.body, "+14155559876"
      assert_includes @response.body, "Imported from OpenAI Realtime"
    end
  end
end
