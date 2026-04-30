require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  test "normalizes key before validation" do
    app_setting = AppSetting.create!(key: " sample_test_key ", value: "AC123")

    assert_equal "SAMPLE_TEST_KEY", app_setting.key
  end

  test "fetch prefers database value over environment" do
    original = ENV["TWILIO_ACCOUNT_SID"]
    ENV["TWILIO_ACCOUNT_SID"] = "env-value"

    assert_equal "AC_fixture_sid", AppSetting.fetch("TWILIO_ACCOUNT_SID")
  ensure
    ENV["TWILIO_ACCOUNT_SID"] = original
  end

  test "fetch falls back to environment when key is missing from database" do
    original = ENV["MISSING_TEST_KEY"]
    ENV["MISSING_TEST_KEY"] = "env-fallback"

    assert_equal "env-fallback", AppSetting.fetch("MISSING_TEST_KEY")
  ensure
    ENV["MISSING_TEST_KEY"] = original
  end

  test "detects sensitive keys" do
    assert AppSetting.sensitive_key?("TWILIO_AUTH_TOKEN")
    assert AppSetting.sensitive_key?("ATHENA_IDEAS_DISCORD_WEBHOOK_URL")
    assert AppSetting.sensitive_key?("GOOGLE_CALENDAR_TOOL_URL_BEARER")
    assert_not AppSetting.sensitive_key?("PUBLIC_BASE_URL")
    assert_not AppSetting.sensitive_key?("TWILIO_ACCOUNT_SID")
  end

  test "filters generic app setting secret values" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter({ "app_setting" => { "key" => "TWILIO_AUTH_TOKEN", "value" => "secret-value" } })

    assert_equal "[FILTERED]", filtered.dig("app_setting", "value")
  end
end
