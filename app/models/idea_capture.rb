class IdeaCapture < ApplicationRecord
  STATUSES = %w[captured reported reviewed archived].freeze
  REVIEW_STATUSES = %w[reviewed archived captured].freeze
  SEARCH_FIELDS = %w[title problem proposed_solution impact next_step department category].freeze
  CSV_HEADERS = [ "ID", "Title", "Category", "Department", "Status", "Caller", "Problem", "Proposed solution", "Impact hypothesis", "Next step", "Conversation ID", "Captured at" ].freeze

  belongs_to :conversation

  validates :title, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.search(query)
    return all if query.blank?

    pattern = "%#{sanitize_sql_like(query.to_s.strip)}%"
    where(SEARCH_FIELDS.map { |field| "idea_captures.#{field} LIKE :query ESCAPE '\\'" }.join(" OR "), query: pattern)
  end

  # Yield a CSV a row at a time so a large export does not load the entire
  # library into memory. Quoting every cell preserves commas and line breaks.
  def self.each_csv_row
    ideas = all
    Enumerator.new do |rows|
      rows << csv_line(CSV_HEADERS)
      ideas.includes(conversation: :customer).find_each(batch_size: 500, order: :desc) do |idea|
        rows << csv_line([
          idea.id, idea.title, idea.category, idea.department, idea.status,
          idea.caller_name, idea.problem, idea.proposed_solution, idea.impact,
          idea.next_step, idea.conversation_id, idea.created_at.utc.iso8601
        ])
      end
    end
  end

  def self.csv_line(values)
    values.map do |value|
      text = value.to_s
      # Spreadsheet applications may interpret even a quoted CSV cell as a
      # formula. Check past leading whitespace and control characters too.
      text = "'#{text}" if text.match?(/\A[\p{Space}\p{Cc}\p{Cf}]*[=+\-@\t\r\n\uFF1D\uFF0B\uFF0D\uFF20]/)
      "\"#{text.gsub('"', '""')}\""
    end.join(",") + "\r\n"
  end

  def transition_review_status!(new_status)
    raise ArgumentError, "Unsupported idea review status." unless REVIEW_STATUSES.include?(new_status)

    with_lock do
      return false if status == new_status

      previous_status = status
      update!(status: new_status)
      call_state = conversation.call_state || CallState.ensure_for_conversation(conversation, provider: "athena")
      call_state.sidecar_events.create!(
        conversation: conversation,
        source: "human_review",
        kind: "idea_capture.#{new_status == "captured" ? "reopened" : new_status}",
        provider: "athena",
        payload: { idea_capture_id: id, previous_status: previous_status, status: new_status },
        changes_call_behavior: false,
        requires_review: new_status == "captured",
        occurred_at: Time.current
      )
      true
    end
  end

  def caller_name
    conversation.customer&.name.presence || "Unknown caller"
  end
end
