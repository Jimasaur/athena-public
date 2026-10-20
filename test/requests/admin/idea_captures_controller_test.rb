require "test_helper"

module Admin
  class IdeaCapturesControllerTest < ActionDispatch::IntegrationTest
    setup do
      IdeaCapture.delete_all
      @idea = create_idea(title: "Eligibility exception queue", category: "Automation", department: "Patient access")
    end

    test "library combines search category and status filters and exposes selected values" do
      create_idea(title: "Other automation", category: "Automation")
      create_idea(title: "Eligibility denials", category: "Denials")
      create_idea(title: "Archived eligibility", category: "Automation", status: "archived")

      get admin_idea_captures_path, params: { q: "eligibility", category: "Automation", status: "captured" }

      assert_response :success
      assert_select "a[data-idea-id]", count: 1
      assert_select "a[data-idea-id='#{@idea.id}']"
      assert_select "input[name=q][value=eligibility]"
      assert_select "select[name=category] option[selected]", text: "Automation"
      assert_select "select[name=status] option[selected]", text: "Captured"
      assert_includes response.body, "1 matching of 4 total"
    end

    test "pagination has stable newest ordering accurate counts and bounded page input" do
      25.times { |index| create_idea(title: "Idea #{index}", category: "Automation") }

      get admin_idea_captures_path, params: { category: "Automation" }

      assert_response :success
      assert_select "a[data-idea-id]", count: 25
      assert_select "a[data-idea-id='#{@idea.id}']", count: 0
      assert_includes response.body, "Showing 1–25 of 26"
      assert_select "a[rel=next]" do |links|
        assert_includes links.first["href"], "category=Automation"
        assert_includes links.first["href"], "page=2"
      end

      get admin_idea_captures_path, params: { page: "999999999999999999999" }

      assert_response :success
      assert_select "a[data-idea-id]", count: 1
      assert_select "a[data-idea-id='#{@idea.id}']"
      assert_includes response.body, "Page 2 of 2"

      get admin_idea_captures_path, params: { page: "-5" }
      assert_response :success
      assert_select "a[data-idea-id]", count: 25
    end

    test "CSV exports all matching pages and protects spreadsheet cells" do
      @idea.update!(title: "=Eligibility command")
      26.times { |index| create_idea(title: "Eligibility #{index}", category: "Automation") }
      create_idea(title: "Excluded item", category: "Denials")

      get admin_idea_captures_path(format: :csv), params: { q: "eligibility", category: "Automation", status: "captured", page: 2 }

      assert_response :success
      assert_equal "text/csv", response.media_type
      assert_includes response.headers["Content-Disposition"], "attachment"
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal 28, response.body.lines.size
      assert_includes response.body, "\"'=Eligibility command\""
      assert_not_includes response.body, "Excluded item"
    end

    test "empty search keeps filters usable and offers a reset" do
      get admin_idea_captures_path, params: { q: "no matching idea" }

      assert_response :success
      assert_select "h2", text: "No ideas match these filters"
      assert_select "a", text: "Show all ideas"
      assert_includes response.body, "0 matching of 1 total"
    end

    test "detail explains missing evidence and offers review actions" do
      get admin_idea_capture_path(@idea)

      assert_response :success
      assert_select "button", text: "Mark reviewed"
      assert_select "button", text: "Archive idea"
      assert_includes response.body, "No transcript excerpt is attached"
    end

    test "review archive and reopen only change library status and append audit events" do
      assert_no_difference -> { ActionDraft.where(status: "executed").count } do
        patch review_admin_idea_capture_path(@idea), params: { status: "executed" }
        assert_redirected_to admin_idea_capture_path(@idea)
        assert_equal "reviewed", @idea.reload.status

        patch archive_admin_idea_capture_path(@idea)
        assert_redirected_to admin_idea_capture_path(@idea)
        assert_equal "archived", @idea.reload.status

        patch reopen_admin_idea_capture_path(@idea)
        assert_redirected_to admin_idea_capture_path(@idea)
        assert_equal "captured", @idea.reload.status
      end
      assert_equal 3, @idea.conversation.sidecar_events.where(source: "human_review").count
    end

    test "library exports and review actions require admin authentication when configured" do
      AppSetting.create!(key: "ADMIN_AUTH_REQUIRED", value: "true")

      get admin_idea_captures_path(format: :csv)
      assert_response :unauthorized

      assert_no_difference -> { SidecarEvent.count } do
        patch review_admin_idea_capture_path(@idea)
        assert_response :unauthorized
      end
      assert_equal "captured", @idea.reload.status
    end

    private

    def create_idea(attributes = {})
      IdeaCapture.create!({ conversation: conversations(:one), title: "Improvement idea", problem: "A workflow needs attention" }.merge(attributes))
    end
  end
end
