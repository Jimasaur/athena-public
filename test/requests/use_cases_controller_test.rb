require "test_helper"

class UseCasesControllerTest < ActionDispatch::IntegrationTest
  test "index renders the use case portfolio" do
    get use_cases_path

    assert_response :success
    assert_select "h1", text: /Four paths/
    assert_select "a[href='#{use_case_path("rev-cycle-ideation-session")}']"
    assert_select "a[href='#{use_case_path("automation-opportunity-discovery")}']"
  end

  test "show renders a use case marketing page" do
    get use_case_path("rev-cycle-ideation-session")

    assert_response :success
    assert_select "h1", text: /retreat-ready revenue cycle ideas/
    assert_select "h2", text: "Core actions"
    assert_select "h2", text: "Real workflows to design around."
    assert_select "h3", text: "Rough Idea Capture"
    assert_select "code", text: "idea_capture"
  end

  test "all configured use cases render" do
    UseCasesController::USE_CASES.each do |use_case|
      assert_equal 10, use_case[:user_stories].length, "#{use_case[:slug]} should have 10 stories"

      get use_case_path(use_case[:slug])

      assert_response :success
      assert_select "title", text: /#{Regexp.escape(use_case[:title])}/
      assert_select "article", count: 10
    end
  end

  test "unknown use case returns not found" do
    get use_case_path("missing")

    assert_response :not_found
  end
end
