class WorkItem < ApplicationRecord
  KINDS = %w[request issue opportunity follow_up].freeze
  PRIORITIES = %w[low normal high urgent].freeze
  STATUSES = %w[needs_review ready in_progress waiting resolved archived].freeze
  CLOSED_STATUSES = %w[resolved archived].freeze
  OPEN_STATUSES = (STATUSES - CLOSED_STATUSES).freeze
  INTAKE_SOURCES = %w[voice web manual].freeze
  TITLE_MAX_LENGTH = 200
  DESCRIPTION_MAX_LENGTH = 20_000
  NEXT_STEP_MAX_LENGTH = 2_000
  OWNER_MAX_LENGTH = 120
  RESOLUTION_NOTE_MAX_LENGTH = 5_000
  SEARCH_FIELDS = %w[title description next_step owner resolution_note].freeze
  AUDITED_FIELDS = %w[title kind description next_step owner priority status due_on resolution_note resolved_at intake_source demo conversation_id idea_capture_id].freeze
  QUEUE_ORDER = "CASE work_items.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 WHEN 'low' THEN 3 ELSE 4 END, CASE WHEN work_items.due_on IS NULL THEN 1 ELSE 0 END, work_items.due_on ASC, work_items.created_at ASC, work_items.id ASC".freeze

  belongs_to :conversation, optional: true
  belongs_to :idea_capture, optional: true
  has_many :events, -> { order(created_at: :asc, id: :asc) }, class_name: "WorkItemEvent", inverse_of: :work_item, dependent: :destroy
  has_many :work_item_handoffs, dependent: :destroy

  # Controllers and services set this from their authenticated execution context,
  # never from a caller-supplied reviewer name.
  attr_accessor :audit_actor

  before_validation :normalize_text
  before_save :synchronize_resolution_timestamp
  after_create :record_creation_event
  after_update :record_update_event

  validates :title, :kind, :priority, :status, :intake_source, presence: true
  validates :title, length: { minimum: 3, maximum: TITLE_MAX_LENGTH }
  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }
  validates :next_step, length: { maximum: NEXT_STEP_MAX_LENGTH }
  validates :owner, length: { maximum: OWNER_MAX_LENGTH }
  validates :resolution_note, length: { maximum: RESOLUTION_NOTE_MAX_LENGTH }
  validates :resolution_note, presence: true, if: :resolved?
  validates :kind, inclusion: { in: KINDS }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :intake_source, inclusion: { in: INTAKE_SOURCES }
  validates :idea_capture_id, uniqueness: true, allow_nil: true
  validate :valid_due_date

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :overdue, -> { open.where("work_items.due_on < ?", Date.current) }
  scope :for_queue, -> { reorder(Arel.sql(QUEUE_ORDER)) }

  def self.search(query)
    return all if query.blank?

    pattern = "%#{sanitize_sql_like(query.to_s.strip)}%"
    where(SEARCH_FIELDS.map { |field| "work_items.#{field} LIKE :query ESCAPE '\\'" }.join(" OR "), query: pattern)
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  def resolved?
    status == "resolved"
  end

  def archived?
    status == "archived"
  end

  def overdue?
    open? && due_on.present? && due_on < Date.current
  end

  private

  def normalize_text
    self.title = title.to_s.squish
    self.owner = owner.to_s.squish.presence
    %w[description next_step resolution_note].each do |field|
      self[field] = self[field].to_s.strip.presence
    end
  end

  def valid_due_date
    return if due_on_before_type_cast.blank? || due_on.present?

    errors.add(:due_on, "must be a valid date")
  end

  def synchronize_resolution_timestamp
    return unless new_record? || will_save_change_to_status?

    self.resolved_at = resolved? ? Time.current : nil
  end

  def record_creation_event
    changes = attributes.slice(*AUDITED_FIELDS).compact.transform_values { |value| [ nil, value ] }
    record_audit_event("created", changes)
  end

  def record_update_event
    changes = saved_changes.slice(*AUDITED_FIELDS)
    return if changes.empty?

    record_audit_event(changes.key?("status") ? "status_changed" : "updated", changes)
  ensure
    self.audit_actor = nil
  end

  def record_audit_event(event_type, changes)
    events.create!(
      event_type: event_type,
      actor: audit_actor.to_s.squish.presence || "system",
      details: { changes: changes.as_json, lock_version: lock_version }
    )
  ensure
    self.audit_actor = nil
  end
end
