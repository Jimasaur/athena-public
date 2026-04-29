require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "dashboard renders demo launchpad and readiness" do
      get admin_root_path

      assert_response :success
      assert_select "h1", text: "Athena Control"
      assert_select "h2", text: "Guided Demo"
      assert_select "h2", text: "Readiness"
      assert_select "h2", text: "Latest Calls"
      assert_includes @response.body, "script/seed_demo_conversation"
      assert_includes @response.body, "Rev Cycle Ideation Session"
    end
  end
end
