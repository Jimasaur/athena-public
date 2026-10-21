require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "dashboard renders demo launchpad and readiness" do
      get admin_overview_path

      assert_response :success
      assert_select "h1", text: "Workspace overview"
      assert_select "h2", text: "Guided Demo"
      assert_select "h2", text: "Readiness"
      assert_select "h2", text: "Latest Calls"
      assert_includes @response.body, "script/seed_demo_conversation"
      assert_includes @response.body, "Rev Cycle Ideation Session"
      assert_includes @response.body, "Local synthetic demo"
      assert_includes @response.body, "Configuration inventory only"
      assert_includes @response.body, "Needs review"
    end
  end
end
