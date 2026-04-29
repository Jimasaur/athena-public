class GemmaMailApprovalJob < ApplicationJob
  queue_as :default

  MAX_DELIVERY_ATTEMPTS = 4
  RETRY_WAIT_SECONDS = [ 30, 90, 180 ].freeze

  def perform(call_state_id, payload)
    call_state = CallState.includes(:conversation).find(call_state_id)
    payload = payload.to_h.with_indifferent_access
    payload[:approval_id] ||= "athena-conversation-#{call_state.conversation_id}"
    payload[:approval_delivery_attempt] = delivery_attempt(payload)

    return if delivered?(call_state, payload[:approval_id])

    result = GemmaMailDiscordApprovalRequestService.new(
      payload: payload.merge(approval_workflow: true, mode: "approval"),
      channel: payload[:approval_channel],
      target: payload[:approval_target]
    ).call
    create_result_event(call_state, payload, result)
    schedule_retry(call_state, payload, result) if retry_delivery?(result, payload[:approval_delivery_attempt])
  end

  private

  def delivery_attempt(payload)
    attempt = payload[:approval_delivery_attempt].to_i
    attempt.positive? ? attempt : 1
  end

  def delivered?(call_state, approval_id)
    return false if approval_id.blank?

    call_state.sidecar_events.where(
      kind: [ "email_approval.sent_to_discord", "email_approval.sent", "email_approval.cancelled" ]
    ).where("payload ->> 'approval_id' = ?", approval_id).exists?
  end

  def create_result_event(call_state, payload, result)
    ok = result[:ok] && result[:delivery_status] == "approval_requested"
    call_state.sidecar_events.create!(
      conversation: call_state.conversation,
      source: "gemma_mail_handoff",
      kind: ok ? "email_approval.sent_to_discord" : "email_approval.failed",
      provider: "openclaw",
      payload: {
        recipient: payload[:to],
        subject: payload[:subject],
        body: payload[:body],
        request: payload[:request],
        approval_id: payload[:approval_id],
        category: payload[:category],
        approval_channel: payload[:approval_channel],
        approval_target: payload[:approval_target],
        approval_delivery_attempt: payload[:approval_delivery_attempt],
        result: result.slice(:ok, :agent, :session_id, :channel, :reply_to, :mode, :action, :delivery_status, :reply, :error)
      }.compact,
      evidence: {
        conversation_id: call_state.conversation_id
      },
      changes_call_behavior: false,
      requires_review: !ok,
      occurred_at: Time.current
    )
  end

  def retry_delivery?(result, attempt)
    return false if result[:ok] && result[:delivery_status] == "approval_requested"
    return false if attempt >= MAX_DELIVERY_ATTEMPTS

    result[:error].to_s.match?(/Discord approval request failed|timeout|Missing Access/i)
  end

  def schedule_retry(call_state, payload, result)
    next_attempt = payload[:approval_delivery_attempt].to_i + 1
    wait_seconds = RETRY_WAIT_SECONDS.fetch(payload[:approval_delivery_attempt].to_i - 1, RETRY_WAIT_SECONDS.last)
    retry_payload = payload.merge(approval_delivery_attempt: next_attempt)

    call_state.sidecar_events.create!(
      conversation: call_state.conversation,
      source: "gemma_mail_handoff",
      kind: "email_approval.retry_scheduled",
      provider: "openclaw",
      payload: {
        recipient: payload[:to],
        subject: payload[:subject],
        approval_id: payload[:approval_id],
        category: payload[:category],
        approval_channel: payload[:approval_channel],
        approval_target: payload[:approval_target],
        approval_delivery_attempt: next_attempt,
        wait_seconds: wait_seconds,
        result: result.slice(:ok, :error)
      }.compact,
      evidence: {
        conversation_id: call_state.conversation_id
      },
      changes_call_behavior: false,
      requires_review: false,
      occurred_at: Time.current
    )

    self.class.set(wait: wait_seconds.seconds).perform_later(call_state.id, retry_payload)
  end
end
