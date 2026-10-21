require "test_helper"

class IdeaCaptureTest < ActiveSupport::TestCase
  setup do
    @idea = IdeaCapture.create!(
      conversation: conversations(:one),
      title: "Reduce manual follow-up",
      category: "Automation",
      department: "Patient access",
      problem: "Staff repeat eligibility checks",
      proposed_solution: "Queue exceptions for review",
      impact: "Measure staff time saved",
      next_step: "Find a pilot owner"
    )
  end

  test "search finds source fields and treats wildcard characters literally" do
    assert_includes IdeaCapture.search("eligibility"), @idea
    assert_includes IdeaCapture.search("PATIENT ACCESS"), @idea
    assert_includes IdeaCapture.search("pilot owner"), @idea
    assert_not_includes IdeaCapture.search("%"), @idea
    assert_not_includes IdeaCapture.search("_"), @idea

    @idea.update!(impact: "Save 10% of follow_up time")
    assert_includes IdeaCapture.search("10%"), @idea
    assert_includes IdeaCapture.search("follow_up"), @idea
    assert_not_includes IdeaCapture.search("follow%up"), @idea
  end

  test "csv preserves punctuation and line breaks" do
    assert_equal "\"a,b\",\"He said \"\"yes\"\"\",\"two\nlines\"\r\n",
      IdeaCapture.csv_line([ "a,b", 'He said "yes"', "two\nlines" ])
  end

  test "csv neutralizes formulas including whitespace and control character prefixes" do
    [ "=SUM(1,2)", "+cmd", "-cmd", "@SUM(A1)", "  =1+1", "\t=1", "\rtext", " \ntext", "\u0000=1", "\uFEFF=1", "\uFF1D1+1" ].each do |value|
      assert IdeaCapture.csv_line([ value ]).start_with?("\"'"), "Unsafe cell: #{value.inspect}"
    end
    assert_equal "\"Ordinary text\",\"\"\r\n", IdeaCapture.csv_line([ "Ordinary text", nil ])
  end

  test "export protects every caller supplied text field and retains the requested scope" do
    @idea.conversation.customer.update!(name: "=caller")
    @idea.update!(
      title: "=title", category: "+category", department: "-department",
      problem: "@problem", proposed_solution: "=solution", impact: "+impact", next_step: "-next"
    )
    IdeaCapture.create!(conversation: conversations(:two), title: "Unrelated idea")

    rows = IdeaCapture.where(id: @idea.id).each_csv_row.to_a

    assert_equal 2, rows.size
    %w[=title +category -department =caller @problem =solution +impact -next].each do |value|
      assert_includes rows.last, "\"'#{value}\""
    end
    assert_not_includes rows.join, "Unrelated idea"
  end

  test "review archive and reopen preserve the idea and create audit events once" do
    assert_difference -> { SidecarEvent.count }, 3 do
      assert @idea.transition_review_status!("reviewed")
      assert @idea.transition_review_status!("archived")
      assert @idea.transition_review_status!("captured")
    end

    assert_equal "captured", @idea.reload.status
    events = @idea.conversation.sidecar_events.where(source: "human_review").order(:id).last(3)
    assert_equal %w[idea_capture.reviewed idea_capture.archived idea_capture.reopened], events.map(&:kind)
    assert_equal @idea.id, events.last.payload["idea_capture_id"]
    assert_equal "archived", events.last.payload["previous_status"]
    assert events.last.requires_review
    assert_not events.any?(&:changes_call_behavior)

    assert_no_difference -> { SidecarEvent.count } do
      assert_not @idea.transition_review_status!("captured")
    end
  end

  test "review workflow refuses arbitrary statuses" do
    assert_raises(ArgumentError) { @idea.transition_review_status!("executed") }
    assert_equal "captured", @idea.reload.status
  end
end
