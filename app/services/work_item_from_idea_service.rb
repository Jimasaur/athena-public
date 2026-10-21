class WorkItemFromIdeaService
  def initialize(idea_capture:, actor: "capture")
    @idea_capture = idea_capture
    @actor = actor
  end

  def call
    raise ArgumentError, "A persisted idea capture is required." unless @idea_capture&.persisted?

    # The source lock serializes conversions on databases that support row
    # locks; the unique index also prevents duplicate links under a race.
    WorkItem.transaction(requires_new: true) do
      @idea_capture.lock!
      WorkItem.find_by(idea_capture_id: @idea_capture.id) || create_work_item
    end
  rescue ActiveRecord::RecordNotUnique
    WorkItem.find_by!(idea_capture_id: @idea_capture.id)
  rescue ActiveRecord::RecordInvalid => error
    existing = WorkItem.find_by(idea_capture_id: @idea_capture.id)
    return existing if existing && error.record.errors.of_kind?(:idea_capture_id, :taken)

    raise
  end

  private

  def create_work_item
    WorkItem.create!(
      conversation: @idea_capture.conversation,
      idea_capture: @idea_capture,
      title: work_item_title,
      kind: "opportunity",
      description: description,
      next_step: @idea_capture.next_step.to_s.truncate(WorkItem::NEXT_STEP_MAX_LENGTH),
      intake_source: intake_source,
      demo: demo_source?,
      audit_actor: @actor
    )
  end

  def work_item_title
    title = @idea_capture.title.to_s.squish
    title = "Captured idea: #{title}" if title.length < 3
    title.truncate(WorkItem::TITLE_MAX_LENGTH)
  end

  def description
    [
      [ "Problem", @idea_capture.problem ],
      [ "Proposed solution", @idea_capture.proposed_solution ],
      [ "Impact hypothesis", @idea_capture.impact ]
    ].filter_map do |label, value|
      "#{label}: #{value.to_s.strip}" if value.present?
    end.join("\n\n").truncate(WorkItem::DESCRIPTION_MAX_LENGTH)
  end

  def intake_source
    case @idea_capture.conversation.channel
    when "voice" then "voice"
    when "web", "chat" then "web"
    else "manual"
    end
  end

  def demo_source?
    @idea_capture.conversation.twilio_call_sid.to_s.start_with?("DEMO-") ||
      (@idea_capture.payload.is_a?(Hash) && @idea_capture.payload["demo"] == true)
  end
end
