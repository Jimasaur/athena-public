require "test_helper"

module Admin
  class DemoScenariosControllerTest < ActionDispatch::IntegrationTest
    test "index renders live call launchpad and all scenario cards" do
      get admin_demo_scenarios_path

      assert_response :success
      assert_select "h1", text: "Demo Scenarios"
      assert_select "h2", text: "Call Athena and show the real chain"
      assert_includes @response.body, "Functions to show off"
      assert_includes @response.body, "Capture this as a rev cycle retreat idea."
      assert_includes @response.body, "Run an Athena status check."
      assert_includes @response.body, "Seed all demos"
      assert_includes @response.body, "Live monitor"
      assert_includes @response.body, "Configuration inventory only"
      assert_includes @response.body, "seeded results do not demonstrate live delivery"
      assert_operator @response.body.index("Start here"), :<, @response.body.index("Live call demo")
      DemoScenarioCatalog.all.each do |scenario|
        assert_includes @response.body, scenario[:title]
      end
    end

    test "launch seeds scenario and redirects to conversation" do
      scenario = DemoScenarioCatalog.fetch("automation-opportunity-discovery")

      assert_difference -> { Conversation.count }, 1 do
        assert_difference -> { IdeaCapture.count }, 1 do
          post launch_admin_demo_scenario_path(scenario[:slug])
        end
      end

      conversation = Conversation.order(:created_at).last
      assert_redirected_to admin_conversation_path(conversation)
      assert_equal scenario[:slug], conversation.call_state.use_case_slug
      assert_equal scenario[:action_status], conversation.action_drafts.first.status
      assert conversation.sidecar_events.where(kind: "state_patch.applied").exists?
      assert conversation.sidecar_events.where(kind: "idea_capture.captured").exists?
    end

    test "live monitor excludes newer synthetic conversations" do
      seeded = DemoScenarioSeedService.new(slug: DemoScenarioCatalog.all.first[:slug]).call

      get admin_demo_scenarios_path

      assert_response :success
      assert_select "a[href='#{admin_conversation_path(seeded)}']", text: /Open newest call/, count: 0
    end

    test "seed all creates all scenario conversations" do
      assert_difference -> { Conversation.where("twilio_call_sid LIKE ?", "DEMO-%").count }, DemoScenarioCatalog.all.size do
        post seed_all_admin_demo_scenarios_path
      end

      assert_redirected_to admin_demo_scenarios_path
      assert_equal "All demo scenarios are ready.", flash[:notice]
    end
  end
end
