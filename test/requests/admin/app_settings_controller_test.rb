require "test_helper"

module Admin
  class AppSettingsControllerTest < ActionDispatch::IntegrationTest
    test "index lists config variables" do
      get admin_app_settings_path

      assert_response :success
      assert_includes @response.body, "TWILIO_ACCOUNT_SID"
      assert_includes @response.body, "Edit TWILIO_ACCOUNT_SID"
      assert_includes @response.body, ">Save</span>"
      assert_includes @response.body, "OpenAI Realtime"
      assert_includes @response.body, "OPENAI_REALTIME_INTERRUPT_RESPONSE"
      assert_includes @response.body, "OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED"
      assert_includes @response.body, "OPENAI_REALTIME_SESSION_OVERRIDES_JSON"
    end

    test "create adds a config variable" do
      assert_difference -> { AppSetting.count }, 1 do
        post admin_app_settings_path, params: {
          app_setting: {
            key: "ATHENA_TOOL_SECRET",
            value: "test-api-key"
          }
        }
      end

      assert_redirected_to admin_app_settings_path
      assert_equal "test-api-key", AppSetting.find_by(key: "ATHENA_TOOL_SECRET").value
    end

  test "update edits an existing config variable" do
      app_setting = app_settings(:public_base_url)

      patch admin_app_setting_path(app_setting), params: {
        app_setting: {
          value: "https://updated.example.test"
        }
      }

      assert_redirected_to admin_app_settings_path
    assert_equal "https://updated.example.test", app_setting.reload.value
  end

  test "index masks sensitive values" do
    AppSetting.create!(key: "ATHENA_TOOL_SECRET", value: "super-secret-tool-value")

    get admin_app_settings_path

    assert_response :success
    assert_includes @response.body, "Stored secret"
    assert_not_includes @response.body, "super-secret-tool-value"
    assert_not_includes @response.body, "fixture_auth_token"
  end

  test "blank sensitive update preserves existing value" do
    app_setting = app_settings(:twilio_auth_token)

    patch admin_app_setting_path(app_setting), params: {
      app_setting: {
        value: ""
      }
    }

    assert_redirected_to admin_app_settings_path
    assert_equal "fixture_auth_token", app_setting.reload.value
  end

  test "blank non-sensitive update clears existing value" do
    app_setting = app_settings(:public_base_url)

    patch admin_app_setting_path(app_setting), params: {
      app_setting: {
        value: ""
      }
    }

    assert_redirected_to admin_app_settings_path
    assert_equal "", app_setting.reload.value
  end

    test "destroy removes a config variable" do
      app_setting = app_settings(:twilio_auth_token)

      assert_difference -> { AppSetting.count }, -1 do
        delete admin_app_setting_path(app_setting)
      end

      assert_redirected_to admin_app_settings_path
    end

    test "realtime updates curated settings and preserves blank secret" do
      AppSetting.create!(key: "OPENAI_API_KEY", value: "sk-existing")

      patch realtime_admin_app_settings_path, params: {
        realtime: {
          "OPENAI_API_KEY" => "",
          "OPENAI_REALTIME_MODEL" => "gpt-realtime-1.5",
          "OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED" => "false",
          "OPENAI_REALTIME_INTERRUPT_RESPONSE" => "false",
          "OPENAI_REALTIME_VAD_THRESHOLD" => "0.7"
        }
      }

      assert_redirected_to admin_app_settings_path
      assert_equal "sk-existing", AppSetting.fetch("OPENAI_API_KEY")
      assert_equal "gpt-realtime-1.5", AppSetting.fetch("OPENAI_REALTIME_MODEL")
      assert_equal "false", AppSetting.fetch("OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED")
      assert_equal "false", AppSetting.fetch("OPENAI_REALTIME_INTERRUPT_RESPONSE")
      assert_equal "0.7", AppSetting.fetch("OPENAI_REALTIME_VAD_THRESHOLD")
    end
  end
end
