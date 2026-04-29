require "test_helper"

module Admin
  class AuthenticationTest < ActionDispatch::IntegrationTest
    test "admin remains open when credentials are not configured" do
      get admin_app_settings_path

      assert_response :success
    end

    test "admin requires basic auth when credentials are configured" do
      AppSetting.create!(key: "ADMIN_USERNAME", value: "demo")
      AppSetting.create!(key: "ADMIN_PASSWORD", value: "secret")

      get admin_app_settings_path

      assert_response :unauthorized

      get admin_app_settings_path, headers: {
        "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("demo", "secret")
      }

      assert_response :success
    end
  end
end
