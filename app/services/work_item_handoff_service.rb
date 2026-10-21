require "digest"
require "json"
require "net/http"
require "securerandom"

class WorkItemHandoffService
  Result = Struct.new(:ok, :handoff, :error, keyword_init: true) do
    def ok?
      ok
    end
  end

  ENABLED_SETTING = "ATHENA_HANDOFF_ENABLED"
  URL_SETTING = "ATHENA_HANDOFF_WEBHOOK_URL"
  BEARER_SETTING = "ATHENA_HANDOFF_WEBHOOK_BEARER"
  RECONCILIATION_GRACE = 1.minute
  SNAPSHOT_FIELDS = %w[id title kind description next_step owner priority status due_on resolution_note resolved_at].freeze

  attr_reader :work_item, :handoff

  def initialize(work_item: nil, handoff: nil, settings: AppSetting, url_policy: OutboundUrlPolicy)
    @handoff = handoff
    @work_item = handoff&.work_item || work_item
    @settings = settings
    @url_policy = url_policy
  end

  def prepare(prepared_by: "admin", simulate: false)
    return failure("A saved work item is required.") unless work_item&.persisted?
    return failure("Preparer is required.") if prepared_by.to_s.strip.blank?

    work_item.with_lock do
      dry_run = ActiveModel::Type::Boolean.new.cast(simulate) || demo_source?
      return failure("Enable the downstream handoff connection before preparing a live handoff.") unless dry_run || enabled?

      destination = dry_run ? nil : configured_url
      return failure("A downstream webhook URL is required.") if !dry_run && destination.blank?
      return failure("Use an HTTPS webhook URL without userinfo, query parameters, or fragments; configure credentials in the bearer setting.") if !dry_run && !valid_destination?(destination)
      if work_item.work_item_handoffs.where(status: WorkItemHandoff::UNCERTAIN_STATUSES).exists?
        return failure("A delivery is unresolved. Reconcile it with evidence before preparing another handoff.")
      end

      payload = payload_snapshot
      digest = snapshot_digest(payload, destination, dry_run)
      if work_item.work_item_handoffs.where(status: "delivered", payload_digest: digest).exists?
        return failure("This exact work item revision has already been handed off in this mode.")
      end

      work_item.work_item_handoffs.where(status: %w[pending_approval approved]).each do |existing|
        return failure("Review or cancel the existing handoff before preparing another.") if existing.work_item_lock_version == work_item.lock_version

        existing.update!(status: "cancelled", error: "Work item changed after preparation.", finished_at: Time.current)
        record_event(existing, "cancelled", prepared_by, reason: existing.error)
      end

      @handoff = work_item.work_item_handoffs.create!(
        payload: payload,
        payload_digest: digest,
        work_item_lock_version: work_item.lock_version,
        destination_url: destination,
        dry_run: dry_run,
        prepared_by: prepared_by,
        idempotency_key: SecureRandom.uuid
      )
      record_event(handoff, "prepared", prepared_by)
      success
    end
  end

  def approve(reviewer:)
    with_handoff_lock do
      return failure("Only a pending handoff can be approved.") unless handoff.status == "pending_approval"
      return invalidate_snapshot(reviewer) unless snapshot_current?
      return failure("Reviewer is required.") if reviewer.to_s.strip.blank?

      handoff.update!(status: "approved", approved_by: reviewer, approved_at: Time.current)
      record_event(handoff, "approved", reviewer)
      success
    end
  end

  def deliver
    claimed = false
    bearer = nil
    claim = with_handoff_lock do
      return failure("Only an approved handoff can be delivered. Uncertain deliveries require reconciliation.") unless handoff.status == "approved"
      return invalidate_snapshot("admin") unless snapshot_current?
      return failure("The downstream handoff connection is disabled.") unless handoff.dry_run? || enabled?

      bearer = @settings.fetch(BEARER_SETTING, nil).to_s.strip unless handoff.dry_run?
      handoff.update!(status: "delivering", delivery_started_at: Time.current, error: nil)
      record_event(handoff, "delivering", handoff.approved_by)
      success
    end
    return claim unless claim.ok
    claimed = true

    if handoff.dry_run?
      return finish_delivery("delivered", response: { "mode" => "simulation", "acknowledged" => false }, event: "simulated")
    end

    policy = @url_policy.external(handoff.destination_url)
    return finish_delivery("failed", error: policy.error) unless policy.ok?

    uri = policy.uri
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Idempotency-Key"] = handoff.idempotency_key
    request["Authorization"] = "Bearer #{bearer}" if bearer.present?
    request.body = JSON.generate(handoff.payload)
    http = @url_policy.prepare_http(uri, policy.ipaddr)
    http.open_timeout = 5
    http.read_timeout = 15
    http.write_timeout = 5
    http.max_retries = 0
    response = http.request(request)
    evidence = response_evidence(response)
    if response.is_a?(Net::HTTPSuccess)
      finish_delivery("delivered", response: evidence.merge("acknowledged" => true))
    else
      finish_delivery("unknown", response: evidence, error: "Webhook returned HTTP #{response.code}. Delivery is unconfirmed; reconcile before preparing another handoff.")
    end
  rescue StandardError => error
    if claimed && handoff&.reload&.status == "delivering"
      finish_delivery("unknown", error: "Delivery result is uncertain (#{error.class.name}). Reconcile before preparing another handoff.")
    else
      failure("Handoff could not be delivered. Reload its recorded status before taking another action.")
    end
  end

  def cancel(reviewer:)
    return failure("Reviewer is required.") if reviewer.to_s.strip.blank?

    with_handoff_lock do
      return failure("An in-progress, uncertain, or acknowledged delivery cannot be cancelled. Reconcile uncertain delivery first.") unless handoff.status.in?(%w[pending_approval approved failed])

      handoff.update!(status: "cancelled", finished_at: Time.current)
      record_event(handoff, "cancelled", reviewer)
      success
    end
  end

  def reconcile(outcome:, reviewer:, note:)
    return failure("Choose delivered or not_delivered and record the evidence used to reconcile this handoff.") unless outcome.in?(%w[delivered not_delivered]) && note.to_s.strip.present? && reviewer.to_s.strip.present?

    with_handoff_lock do
      return failure("Only an in-progress or uncertain delivery can be reconciled.") unless handoff.delivery_uncertain?
      if handoff.status == "delivering" && handoff.delivery_started_at && handoff.delivery_started_at > RECONCILIATION_GRACE.ago
        return failure("The delivery may still be running. Wait at least one minute, then verify the downstream record before reconciliation.")
      end

      acknowledged = outcome == "delivered"
      handoff.update!(
        status: acknowledged ? "delivered" : "failed",
        delivered_at: acknowledged ? Time.current : nil,
        finished_at: Time.current,
        reconciled_by: reviewer,
        reconciled_at: Time.current,
        reconciliation_note: note.to_s.strip,
        error: acknowledged ? nil : "Reviewer confirmed no delivery. A new handoff needs preparation and approval.",
        response: handoff.response.merge("acknowledged" => acknowledged, "reconciled" => true)
      )
      record_event(handoff, "reconciled", reviewer, outcome: outcome, evidence: note.to_s.strip)
      success
    end
  end

  private

  def with_handoff_lock
    return failure("Handoff is required.") unless handoff&.persisted?

    work_item.with_lock do
      handoff.with_lock { yield }
    end
  end

  def snapshot_current?
    handoff.work_item_lock_version == work_item.lock_version &&
      handoff.payload == payload_snapshot &&
      handoff.payload_digest == snapshot_digest(handoff.payload, handoff.destination_url, handoff.dry_run?) &&
      (handoff.dry_run? || (!demo_source? && handoff.destination_url == configured_url))
  end

  def invalidate_snapshot(actor)
    handoff.update!(status: "cancelled", error: "Work item, source mode, or destination changed. Prepare and review a new handoff.", finished_at: Time.current)
    record_event(handoff, "cancelled", actor, reason: handoff.error)
    failure(handoff.error)
  end

  def finish_delivery(status, response: {}, error: nil, event: status)
    handoff.with_lock do
      return failure("The recorded delivery state changed; review reconciliation before proceeding.") unless handoff.status == "delivering"

      handoff.update!(status: status, response: response, error: error, delivered_at: status == "delivered" ? Time.current : nil, finished_at: Time.current)
      record_event(handoff, event, handoff.approved_by, error: error, acknowledgement_only: true)
    end
    status == "delivered" ? success : failure(error)
  end

  def payload_snapshot
    fields = work_item.attributes.slice(*SNAPSHOT_FIELDS).merge("version" => work_item.lock_version)
    JSON.parse(JSON.generate(
      "schema" => "athena.work_item_handoff.v1",
      "work_item" => fields,
      "source" => work_item.attributes.slice("conversation_id", "idea_capture_id", "intake_source", "demo")
    ))
  end

  def snapshot_digest(payload, destination, dry_run)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value("payload" => payload, "destination_url" => destination, "dry_run" => dry_run)))
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [ key, canonical_value(value[key]) ] }
    when Array
      value.map { |item| canonical_value(item) }
    else
      value
    end
  end

  def demo_source?
    return true if work_item.demo?
    return true if ActiveModel::Type::Boolean.new.cast(@settings.fetch("ATHENA_PUBLIC_DEMO_MODE", false))
    return true if work_item.intake_source.to_s.match?(/\A(?:demo|synthetic)\b/i)

    conversation = work_item.conversation
    return true if conversation&.twilio_call_sid.to_s.start_with?("DEMO-")

    markers = [ conversation&.customer&.metadata, conversation&.call_state&.state, work_item.idea_capture&.payload ].compact
    markers.any? do |metadata|
      metadata["demo"].is_a?(Hash) ||
        ActiveModel::Type::Boolean.new.cast(metadata["demo"]) ||
        ActiveModel::Type::Boolean.new.cast(metadata["synthetic"])
    end
  end

  def enabled?
    @settings.fetch(ENABLED_SETTING, false).to_s.strip.downcase == "true"
  end

  def configured_url
    @settings.fetch(URL_SETTING, nil).to_s.strip
  end

  def valid_destination?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
  rescue URI::InvalidURIError
    false
  end

  def response_evidence(response)
    body = response.body.to_s.byteslice(0, 8_000).to_s.scrub
    parsed = JSON.parse(body)
    { "http_status" => response.code.to_i, "body" => parsed }
  rescue JSON::ParserError
    { "http_status" => response.code.to_i, "body" => body }
  end

  def record_event(record, event, actor, details = {})
    work_item.events.create!(
      event_type: "handoff.#{event}",
      actor: actor.to_s.presence || "admin",
      details: {
        "handoff_id" => record.id,
        "status" => record.status,
        "work_item_version" => record.work_item_lock_version,
        "payload_digest" => record.payload_digest,
        "dry_run" => record.dry_run?
      }.merge(details.compact.stringify_keys)
    )
  end

  def success
    Result.new(ok: true, handoff: handoff)
  end

  def failure(error)
    Result.new(ok: false, handoff: handoff, error: error)
  end
end
