class CallState < ApplicationRecord
  DEFAULT_USE_CASE_SLUG = "rev-cycle-ideation-session"
  DEFAULT_SPACE = "healthcare"

  belongs_to :conversation

  has_many :sidecar_events, dependent: :destroy
  has_many :action_drafts, dependent: :destroy

  validates :call_id, :status, :review_status, presence: true
  validates :call_id, uniqueness: true

  def self.ensure_for_conversation(conversation, provider:, call_id: nil, status: nil, use_case_slug: nil, space: nil)
    resolved_call_id = call_id.presence ||
      conversation.twilio_call_sid.presence ||
      "conversation-#{conversation.id}"

    record = find_or_initialize_by(conversation: conversation)
    record.call_id = resolved_call_id
    record.provider = provider.to_s.presence || record.provider
    record.space = space.presence || record.space.presence || DEFAULT_SPACE
    record.use_case_slug = use_case_slug.presence || record.use_case_slug.presence || default_use_case_for(record.provider)
    record.status = status.presence || record.status.presence || "active"
    record.review_status = record.review_status.presence || "pending"
    record.state = default_state_for(conversation, record).merge(record.state || {})
    record.save!
    record
  end

  def self.default_use_case_for(provider)
    DEFAULT_USE_CASE_SLUG
  end

  def self.default_state_for(conversation, record)
    {
      "schema" => "call_state.v1",
      "call_id" => record.call_id,
      "conversation_id" => conversation.id,
      "space" => record.space,
      "use_case_slug" => record.use_case_slug,
      "provider" => record.provider,
      "status" => record.status,
      "caller" => {
        "name" => conversation.customer&.name.presence || "Unknown",
        "phone" => conversation.customer&.phone_number,
        "known_contact" => conversation.customer&.name.present?
      },
      "intent" => {
        "label" => "rev_cycle_ideation",
        "confidence" => 0.0
      },
      "risk" => {
        "level" => "low",
        "reasons" => []
      },
      "active_constraints" => [
        "draft_only_external_actions",
        "voice_responses_short"
      ],
      "allowed_actions" => [
        "lookup",
        "summarize",
        "draft",
        "capture_idea"
      ],
      "handoff_required" => false,
      "next_best_question" => nil,
      "facts" => [],
      "review_status" => record.review_status
    }
  end
end
