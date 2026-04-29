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
end
