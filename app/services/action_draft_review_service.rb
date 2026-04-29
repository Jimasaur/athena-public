class ActionDraftReviewService
  class AlreadyReviewed < StandardError; end

  APPROVE_DECISION = "approve"
  REJECT_DECISION = "reject"
  DECISIONS = [ APPROVE_DECISION, REJECT_DECISION ].freeze

  attr_reader :action_draft, :decision, :reviewer, :reason

  def initialize(action_draft:, decision:, reviewer: "admin", reason: nil)
    @action_draft = action_draft
    @decision = decision.to_s
    @reviewer = reviewer.to_s.presence || "admin"
    @reason = reason.to_s.presence
  end

  def call
    raise ArgumentError, "Unknown action draft review decision: #{decision}" unless DECISIONS.include?(decision)

    action_draft.with_lock do
      raise AlreadyReviewed, "Draft was already #{action_draft.status.humanize.downcase}." unless action_draft.pending_approval?

      decision == APPROVE_DECISION ? approve_draft : reject_draft
      create_review_event
      refresh_call_state_review_status
    end

    { ok: true, action_draft: action_draft }
  end

  private

  def approve_draft
    action_draft.approve!(approved_by: reviewer)
  end

  def reject_draft
    action_draft.reject!(rejected_by: reviewer, reason: reason)
  end

  def create_review_event
    call_state.sidecar_events.create!(
      conversation: action_draft.conversation,
      source: "human_review",
      kind: "action_draft.#{decision == APPROVE_DECISION ? "approved" : "rejected"}",
      provider: call_state.provider,
      payload: review_payload,
      evidence: { "action_draft_id" => action_draft.id },
      changes_call_behavior: false,
      requires_review: false,
      occurred_at: Time.current
    )
  end

  def review_payload
    payload = {
      "action_draft_id" => action_draft.id,
      "action_kind" => action_draft.kind,
      "status" => action_draft.status,
      "reviewer" => reviewer
    }
    payload["reason"] = reason if reason.present?
    payload
  end

  def refresh_call_state_review_status
    next_status =
      if call_state.action_drafts.where(status: ActionDraft::PENDING_APPROVAL_STATUS).exists?
        "pending"
      elsif call_state.action_drafts.where(status: ActionDraft::APPROVED_STATUS).exists?
        "approved"
      else
        "rejected"
      end

    call_state.update!(
      review_status: next_status,
      state: (call_state.state || {}).merge("review_status" => next_status)
    )
  end

  def call_state
    action_draft.call_state
  end
end
