class ActionDraft < ApplicationRecord
  PENDING_APPROVAL_STATUS = "pending_approval"
  APPROVED_STATUS = "approved"
  REJECTED_STATUS = "rejected"
  EXECUTED_STATUS = "executed"
  EXECUTION_FAILED_STATUS = "execution_failed"
  STATUSES = [
    PENDING_APPROVAL_STATUS,
    APPROVED_STATUS,
    REJECTED_STATUS,
    EXECUTED_STATUS,
    EXECUTION_FAILED_STATUS
  ].freeze

  belongs_to :call_state
  belongs_to :conversation

  validates :kind, :status, :created_by, presence: true
  validates :status, inclusion: { in: STATUSES }

  def pending_approval?
    status == PENDING_APPROVAL_STATUS
  end

  def executable?
    status == APPROVED_STATUS || status == EXECUTION_FAILED_STATUS
  end

  def approve!(approved_by:)
    reviewed_at = Time.current
    update!(
      status: APPROVED_STATUS,
      approved_by: approved_by,
      approved_at: reviewed_at,
      external_side_effect: reviewed_external_side_effect(
        approved: true,
        reviewed_at: reviewed_at
      )
    )
  end

  def reject!(rejected_by:, reason: nil)
    reviewed_at = Time.current
    update!(
      status: REJECTED_STATUS,
      approved_by: rejected_by,
      approved_at: reviewed_at,
      external_side_effect: reviewed_external_side_effect(
        approved: false,
        reviewed_at: reviewed_at,
        reason: reason
      )
    )
  end

  def mark_executed!(provider:, external_id:)
    executed_at = Time.current
    update!(
      status: EXECUTED_STATUS,
      external_side_effect: execution_external_side_effect(
        executed: true,
        provider: provider,
        external_id: external_id,
        executed_at: executed_at
      )
    )
  end

  def mark_execution_failed!(provider:, error:)
    attempted_at = Time.current
    update!(
      status: EXECUTION_FAILED_STATUS,
      external_side_effect: execution_external_side_effect(
        executed: false,
        provider: provider,
        error: error,
        attempted_at: attempted_at
      )
    )
  end

  private

  def reviewed_external_side_effect(approved:, reviewed_at:, reason: nil)
    side_effect = (external_side_effect || {}).deep_dup
    side_effect["approved"] = approved
    side_effect["executed"] = false unless side_effect.key?("executed")
    side_effect["reviewed_at"] = reviewed_at.iso8601
    side_effect["rejection_reason"] = reason if reason.present?
    side_effect
  end

  def execution_external_side_effect(executed:, provider:, external_id: nil, executed_at: nil, attempted_at: nil, error: nil)
    side_effect = (external_side_effect || {}).deep_dup
    side_effect["provider"] = provider
    side_effect["executed"] = executed
    side_effect["executed_at"] = executed_at.iso8601 if executed_at.present?
    side_effect["attempted_at"] = attempted_at.iso8601 if attempted_at.present?
    side_effect["external_id"] = external_id if external_id.present?
    side_effect["error"] = error if error.present?
    side_effect
  end
end
