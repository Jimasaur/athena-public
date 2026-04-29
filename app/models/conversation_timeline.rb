class ConversationTimeline
  Entry = Struct.new(
    :occurred_at,
    :source,
    :title,
    :detail,
    :badge,
    :tone,
    :icon,
    keyword_init: true
  )

  def initialize(conversation)
    @conversation = conversation
  end

  def entries
    [
      call_state_entry,
      call_event_entries,
      sidecar_event_entries,
      action_draft_entries
    ].flatten.compact.sort_by { |entry| entry.occurred_at || Time.zone.at(0) }
  end

  private

  attr_reader :conversation

  def call_state_entry
    call_state = conversation.call_state
    return if call_state.blank?

    Entry.new(
      occurred_at: call_state.created_at,
      source: "Athena",
      title: "Call state created",
      detail: [
        call_state.provider.presence,
        call_state.use_case_slug.presence,
        "review #{call_state.review_status}"
      ].compact.join(" · "),
      badge: call_state.status,
      tone: "slate",
      icon: "ti-route"
    )
  end

  def call_event_entries
    conversation.call_events.map do |event|
      Entry.new(
        occurred_at: event.created_at,
        source: "Twilio / voice",
        title: call_event_title(event),
        detail: call_event_detail(event),
        badge: event.status,
        tone: "sky",
        icon: "ti-phone-call"
      )
    end
  end

  def sidecar_event_entries
    conversation.sidecar_events.map do |event|
      Entry.new(
        occurred_at: event.occurred_at || event.created_at,
        source: event.source.to_s.humanize,
        title: sidecar_title(event),
        detail: sidecar_detail(event),
        badge: event.kind,
        tone: sidecar_tone(event),
        icon: sidecar_icon(event)
      )
    end
  end

  def action_draft_entries
    conversation.action_drafts.map do |draft|
      Entry.new(
        occurred_at: action_draft_occurred_at(draft),
        source: draft.created_by.to_s.humanize,
        title: "Draft #{draft.status.humanize.downcase}",
        detail: action_draft_detail(draft),
        badge: draft.kind.to_s.humanize,
        tone: action_draft_tone(draft),
        icon: action_draft_icon(draft)
      )
    end
  end

  def call_event_title(event)
    case event.data&.dig("type")
    when "post_call_transcription"
      "Transcript received"
    when "post_call_audio"
      "Recording received"
    when "twilio_stream_recording"
      "Recording saved"
    else
      "Call #{event.status.to_s.humanize.downcase}"
    end
  end

  def call_event_detail(event)
    parts = []
    parts << event.direction.to_s.humanize if event.direction.present?
    parts << [ event.from_number, event.to_number ].compact_blank.join(" -> ") if event.from_number.present? || event.to_number.present?
    parts << event.transcription.truncate(120) if event.transcription.present?
    parts.compact_blank.join(" · ")
  end

  def sidecar_title(event)
    {
      "summary.created" => "Sidecar summary created",
      "state_patch.applied" => "Live state patch applied",
      "action_draft.created" => "Follow-up draft created",
      "action_draft.approved" => "Draft approved",
      "action_draft.rejected" => "Draft rejected",
      "external_action.executed" => "External action executed",
      "external_action.failed" => "External action failed"
    }.fetch(event.kind, event.kind.to_s.humanize)
  end

  def sidecar_detail(event)
    payload = event.payload || {}
    payload["summary"].presence ||
      payload["next_best_question"].presence ||
      payload["error"].presence ||
      payload["reason"].presence ||
      payload["twilio_message_sid"].presence ||
      payload["action_kind"].to_s.humanize.presence ||
      "Recorded by Athena."
  end

  def sidecar_tone(event)
    case event.kind
    when "external_action.failed", "action_draft.rejected"
      "rose"
    when "external_action.executed", "action_draft.approved"
      "emerald"
    when "action_draft.created", "summary.created", "state_patch.applied"
      "amber"
    else
      "slate"
    end
  end

  def sidecar_icon(event)
    case event.kind
    when "summary.created"
      "ti-sparkles"
    when "state_patch.applied"
      "ti-adjustments-bolt"
    when "action_draft.created"
      "ti-pencil"
    when "action_draft.approved"
      "ti-check"
    when "action_draft.rejected", "external_action.failed"
      "ti-alert-circle"
    when "external_action.executed"
      "ti-send"
    else
      "ti-activity"
    end
  end

  def action_draft_detail(draft)
    side_effect = draft.external_side_effect || {}
    side_effect["error"].presence ||
      side_effect["external_id"].presence ||
      draft.content&.dig("body").to_s.squish.truncate(140).presence ||
      "Draft created for operator review."
  end

  def action_draft_tone(draft)
    case draft.status
    when ActionDraft::EXECUTED_STATUS, ActionDraft::APPROVED_STATUS
      "emerald"
    when ActionDraft::REJECTED_STATUS, ActionDraft::EXECUTION_FAILED_STATUS
      "rose"
    else
      "amber"
    end
  end

  def action_draft_icon(draft)
    case draft.status
    when ActionDraft::EXECUTED_STATUS
      "ti-send"
    when ActionDraft::APPROVED_STATUS
      "ti-check"
    when ActionDraft::REJECTED_STATUS, ActionDraft::EXECUTION_FAILED_STATUS
      "ti-alert-circle"
    else
      "ti-pencil"
    end
  end

  def action_draft_occurred_at(draft)
    side_effect = draft.external_side_effect || {}
    parse_time(side_effect["executed_at"]) ||
      parse_time(side_effect["attempted_at"]) ||
      draft.approved_at ||
      draft.created_at
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
