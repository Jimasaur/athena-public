class ConversationReviewState
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def to_h
    {
      key: key,
      label: label,
      detail: detail,
      next_action: next_action,
      badge_classes: badge_classes,
      panel_classes: panel_classes,
      icon: icon,
      pending_count: pending_drafts.count,
      ready_count: ready_drafts.count,
      failed_count: failed_drafts.count
    }
  end

  private

  def drafts
    @drafts ||= conversation.action_drafts.to_a
  end

  def pending_drafts
    drafts.select(&:pending_approval?)
  end

  def ready_drafts
    drafts.select { |draft| draft.status == ActionDraft::APPROVED_STATUS }
  end

  def failed_drafts
    drafts.select { |draft| draft.status == ActionDraft::EXECUTION_FAILED_STATUS }
  end

  def executed_drafts
    drafts.select { |draft| draft.status == ActionDraft::EXECUTED_STATUS }
  end

  def key
    return :failed if failed_drafts.any?
    return :needs_review if pending_drafts.any?
    return :ready_to_send if ready_drafts.any?
    return :executed if executed_drafts.any?
    return :live if conversation.status == "in_progress"

    :captured
  end

  def label
    {
      failed: "Action failed",
      needs_review: "Needs review",
      ready_to_send: "Ready to send",
      executed: "Action executed",
      live: "Live call",
      captured: "Captured"
    }.fetch(key)
  end

  def detail
    case key
    when :failed
      "#{failed_drafts.count} #{'action'.pluralize(failed_drafts.count)} #{verb(failed_drafts.count, 'needs', 'need')} attention"
    when :needs_review
      "#{pending_drafts.count} #{'draft'.pluralize(pending_drafts.count)} #{verb(pending_drafts.count, 'awaits', 'await')} approval"
    when :ready_to_send
      "#{ready_drafts.count} approved #{'draft'.pluralize(ready_drafts.count)} #{verb(ready_drafts.count, 'is', 'are')} executable"
    when :executed
      "#{executed_drafts.count} #{'action'.pluralize(executed_drafts.count)} #{verb(executed_drafts.count, 'has', 'have')} been executed"
    when :live
      "Transcript and sidecar state are still changing"
    else
      "No approval-gated action is currently queued"
    end
  end

  def next_action
    case key
    when :failed
      "Review the failure and retry or reject the draft."
    when :needs_review
      "Approve or reject the pending draft before any external action happens."
    when :ready_to_send
      "Send the approved SMS when the campaign and recipient checks are ready."
    when :executed
      "Verify the outcome and use the audit trail if follow-up is needed."
    when :live
      "Monitor the call and let the sidecars update state."
    else
      "Review the transcript, then decide whether a manual follow-up is needed."
    end
  end

  def verb(count, singular, plural)
    count == 1 ? singular : plural
  end

  def badge_classes
    {
      failed: "border-[#e8beb9] bg-[#fbecea] text-[#9d332c]",
      needs_review: "border-[#e8beb9] bg-[#fff8f6] text-[#9d332c]",
      ready_to_send: "border-[#bfddd6] bg-[#e8f3ef] text-[#0f766e]",
      executed: "border-[#d8d2f1] bg-[#f0edf9] text-[#6554c0]",
      live: "border-[#bfddd6] bg-[#e8f3ef] text-[#0f766e]",
      captured: "border-[#dfe5dc] bg-[#fffffb] text-[#66716d]"
    }.fetch(key)
  end

  def panel_classes
    {
      failed: "border-[#e8beb9] bg-[#fff8f6]",
      needs_review: "border-[#e8beb9] bg-[#fff8f6]",
      ready_to_send: "border-[#bfddd6] bg-[#f6fbf8]",
      executed: "border-[#d8d2f1] bg-[#fbfaff]",
      live: "border-[#bfddd6] bg-[#f6fbf8]",
      captured: "border-[#dfe5dc] bg-[#fffffb]"
    }.fetch(key)
  end

  def icon
    {
      failed: "ti-alert-circle",
      needs_review: "ti-user-check",
      ready_to_send: "ti-send",
      executed: "ti-shield-check",
      live: "ti-phone-call",
      captured: "ti-clipboard-check"
    }.fetch(key)
  end
end
