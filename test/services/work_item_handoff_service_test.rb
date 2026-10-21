require "test_helper"

class WorkItemHandoffServiceTest < ActiveSupport::TestCase
  class FakeHttp
    attr_accessor :open_timeout, :read_timeout, :write_timeout, :max_retries, :during_request
    attr_reader :requests

    def initialize(response:, error: nil)
      @response = response
      @error = error
      @requests = []
    end

    def request(request)
      @requests << request
      during_request&.call
      raise @error if @error

      @response
    end
  end

  class FakeUrlPolicy
    attr_accessor :error
    attr_reader :urls

    def initialize(http)
      @http = http
      @urls = []
    end

    def external(url)
      @urls << url
      OutboundUrlPolicy::Result.new(ok: error.nil?, uri: URI.parse(url), ipaddr: "93.184.216.34", error: error)
    end

    def prepare_http(_uri, _address)
      @http
    end
  end

  setup do
    @work_item = WorkItem.create!(title: "Review a reporting request", description: "A synthetic unit-test request.")
    @settings = {}
    @http = FakeHttp.new(response: http_response)
    @policy = FakeUrlPolicy.new(@http)
  end

  test "live handoffs default off and preparation never performs DNS or HTTP" do
    result = service.prepare

    assert_not result.ok
    assert_includes result.error, "Enable"
    assert_empty @work_item.work_item_handoffs
    assert_empty @policy.urls
    assert_empty @http.requests

    @settings[WorkItemHandoffService::ENABLED_SETTING] = "replace-this"
    assert_not service.prepare.ok

    enable_connection
    result = service.prepare(prepared_by: "operator")

    assert result.ok
    assert_equal "pending_approval", result.handoff.status
    assert_equal "operator", result.handoff.prepared_by
    assert_equal @work_item.title, result.handoff.payload.dig("work_item", "title")
    assert_equal @work_item.lock_version, result.handoff.work_item_lock_version
    assert_equal "https://handoff.example.org", result.handoff.destination_label
    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "live destinations require HTTPS without embedded credentials or URL secrets" do
    enable_connection
    [ "http://handoff.example.org/work", "https://user:secret@handoff.example.org/work", "https://handoff.example.org/work?token=secret", "https://handoff.example.org/work#secret" ].each do |url|
      @settings[WorkItemHandoffService::URL_SETTING] = url

      result = service.prepare

      assert_not result.ok, url
      assert_includes result.error, "HTTPS", url
    end

    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "unapproved handoffs cannot be delivered" do
    handoff = prepare_live

    result = service(handoff: handoff).deliver

    assert_not result.ok
    assert_equal "pending_approval", handoff.reload.status
    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "approved payload is delivered once with idempotency and acknowledgement separate from resolution" do
    handoff = approve_live
    before_version = @work_item.lock_version
    @settings[WorkItemHandoffService::BEARER_SETTING] = "test-only-bearer"
    concurrent_result = nil
    @http.during_request = -> { concurrent_result = service(handoff: WorkItemHandoff.find(handoff.id)).deliver }

    result = service(handoff: handoff).deliver

    assert result.ok
    assert_not concurrent_result.ok
    assert_equal 1, @http.requests.size
    request = @http.requests.sole
    assert_equal handoff.idempotency_key, request["Idempotency-Key"]
    assert_equal "Bearer test-only-bearer", request["Authorization"]
    assert_equal handoff.payload, JSON.parse(request.body)
    assert_equal 0, @http.max_retries
    assert handoff.reload.acknowledged?
    assert_equal true, handoff.response["acknowledged"]
    assert_equal 200, handoff.response["http_status"]
    assert_equal "needs_review", @work_item.reload.status
    assert_nil @work_item.resolved_at
    assert_equal before_version, @work_item.lock_version
    assert_equal true, @work_item.events.find_by!(event_type: "handoff.delivered").details["acknowledgement_only"]

    assert_not service(handoff: handoff).deliver.ok
    assert_equal 1, @http.requests.size
    assert_not service.prepare.ok
  end

  test "work item edits invalidate both pending and approved snapshots before delivery" do
    handoff = prepare_live
    @work_item.update!(title: "Revised reporting request")

    result = service(handoff: handoff).approve(reviewer: "operator")

    assert_not result.ok
    assert_equal "cancelled", handoff.reload.status
    assert_empty @http.requests

    handoff = approve_live
    @work_item.update!(owner: "Operations lead")

    result = service(handoff: handoff).deliver

    assert_not result.ok
    assert_equal "cancelled", handoff.reload.status
    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "a caller that fails to claim cannot change another in-flight delivery" do
    handoff = approve_live
    handoff.update!(status: "delivering", delivery_started_at: Time.current)
    item = handoff.work_item
    item.define_singleton_method(:with_lock) do |*|
      raise ActiveRecord::StaleObjectError.new(self, "update")
    end

    result = service(handoff: handoff).deliver

    assert_not result.ok
    assert_equal "delivering", handoff.reload.status
    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "approval is bound to exact destination and delivery respects disabled configuration" do
    handoff = approve_live
    @settings[WorkItemHandoffService::ENABLED_SETTING] = "false"

    assert_not service(handoff: handoff).deliver.ok
    assert_equal "approved", handoff.reload.status
    assert_empty @policy.urls

    @settings[WorkItemHandoffService::ENABLED_SETTING] = "true"
    @settings[WorkItemHandoffService::URL_SETTING] = "https://other.example.org/work"

    assert_not service(handoff: handoff).deliver.ok
    assert_equal "cancelled", handoff.reload.status
    assert_empty @http.requests
  end

  test "timeout blocks retries and replacement until human evidence confirms no delivery" do
    handoff = approve_live
    @http = FakeHttp.new(response: nil, error: Net::ReadTimeout.new("test timeout"))
    @policy = FakeUrlPolicy.new(@http)

    result = service(handoff: handoff).deliver

    assert_not result.ok
    assert_equal "unknown", handoff.reload.status
    assert handoff.delivery_uncertain?
    assert_equal 1, @http.requests.size
    assert_not service(handoff: handoff).deliver.ok
    assert_not service.prepare.ok
    assert_not service(handoff: handoff).cancel(reviewer: "operator").ok
    assert_not service(handoff: handoff).reconcile(outcome: "not_delivered", reviewer: "operator", note: "").ok
    assert_equal 1, @http.requests.size

    result = service(handoff: handoff).reconcile(
      outcome: "not_delivered", reviewer: "operator", note: "Confirmed the downstream idempotency log contains no receipt."
    )

    assert result.ok
    assert_equal "failed", handoff.reload.status
    assert_equal "operator", handoff.reconciled_by
    assert_includes handoff.reconciliation_note, "idempotency log"
    assert_not service(handoff: handoff).deliver.ok
    replacement = service.prepare
    assert replacement.ok
    assert_equal "pending_approval", replacement.handoff.status
    assert_not_equal handoff.idempotency_key, replacement.handoff.idempotency_key
    assert_equal 1, @http.requests.size
    assert_equal "needs_review", @work_item.reload.status
  end

  test "non-success HTTP response remains uncertain rather than becoming a retryable failure" do
    handoff = approve_live
    @http = FakeHttp.new(response: http_response(code: "503", body: '{"error":"try later"}'))
    @policy = FakeUrlPolicy.new(@http)

    result = service(handoff: handoff).deliver

    assert_not result.ok
    assert_equal "unknown", handoff.reload.status
    assert_equal 503, handoff.response["http_status"]
    assert_not service.prepare.ok
    assert_equal 1, @http.requests.size
  end

  test "outbound policy rejects unsafe targets before an HTTP request" do
    handoff = approve_live
    @policy.error = "URL resolves to a private or reserved network."

    result = service(handoff: handoff).deliver

    assert_not result.ok
    assert_equal "failed", handoff.reload.status
    assert_includes handoff.error, "private"
    assert_empty @http.requests
    assert service.prepare.ok
  end

  test "reconciliation records observed acknowledgement without resolving work" do
    handoff = approve_live
    handoff.update!(status: "delivering", delivery_started_at: Time.current)

    result = service(handoff: handoff).reconcile(outcome: "delivered", reviewer: "operator", note: "Found receipt downstream.")

    assert_not result.ok
    assert_includes result.error, "still be running"
    handoff.update!(delivery_started_at: 2.minutes.ago)

    result = service(handoff: handoff).reconcile(outcome: "delivered", reviewer: "operator", note: "Found downstream receipt WORK-42 for this idempotency key.")

    assert result.ok
    assert handoff.reload.acknowledged?
    assert_equal true, handoff.response["reconciled"]
    assert_equal "needs_review", @work_item.reload.status
    assert_nil @work_item.resolved_at
    assert_not service.prepare.ok
    assert_empty @http.requests
  end

  test "demo flag and explicit simulations work offline with delivery disabled" do
    @work_item.update!(demo: true)
    result = service.prepare

    assert result.ok
    handoff = result.handoff
    assert handoff.dry_run?
    assert_nil handoff.destination_url
    assert_equal "Simulated handoff", handoff.destination_label
    assert service(handoff: handoff).approve(reviewer: "operator").ok
    assert service(handoff: handoff).deliver.ok
    assert handoff.reload.simulated?
    assert_not handoff.acknowledged?
    assert_equal false, handoff.response["acknowledged"]
    assert @work_item.events.exists?(event_type: "handoff.simulated")
    assert_empty @policy.urls
    assert_empty @http.requests

    @work_item = WorkItem.create!(title: "Manually simulate a handoff")
    assert service.prepare(simulate: true).handoff.dry_run?

    @work_item = WorkItem.create!(title: "Public demonstration request")
    @settings["ATHENA_PUBLIC_DEMO_MODE"] = "true"
    assert service.prepare.handoff.dry_run?
    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "demo conversation and synthetic metadata force simulation even with live settings" do
    enable_connection
    conversation = conversations(:one)
    conversation.update!(twilio_call_sid: "DEMO-UNIT-TEST")
    @work_item.update!(conversation: conversation)

    handoff = service.prepare.handoff
    assert handoff.dry_run?
    assert service(handoff: handoff).approve(reviewer: "operator").ok
    assert service(handoff: handoff).deliver.ok

    conversation.update!(twilio_call_sid: "CA-unit-test")
    conversation.customer.update!(metadata: { "synthetic" => true })
    @work_item = WorkItem.create!(title: "Synthetic source record", conversation: conversation)
    assert service.prepare.handoff.dry_run?
    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "a source newly marked demo invalidates a live approval instead of sending" do
    conversation = conversations(:one)
    @work_item.update!(conversation: conversation)
    handoff = approve_live
    conversation.customer.update!(metadata: { "demo" => true })

    result = service(handoff: handoff).deliver

    assert_not result.ok
    assert_equal "cancelled", handoff.reload.status
    assert_empty @policy.urls
    assert_empty @http.requests
  end

  test "snapshots cannot be edited and digest validation catches a bypassed mutation" do
    handoff = prepare_live

    assert_raises ActiveRecord::RecordInvalid do
      handoff.update!(payload: handoff.payload.deep_merge("work_item" => { "title" => "Tampered" }))
    end
    handoff.reload.update_columns(payload: handoff.payload.deep_merge("work_item" => { "title" => "Tampered" }))

    assert_not service(handoff: handoff).approve(reviewer: "operator").ok
    assert_equal "cancelled", handoff.reload.status
    assert_empty @http.requests
  end

  test "preparation is unique until explicitly cancelled and writes audit actors" do
    handoff = prepare_live

    assert_not service.prepare.ok
    assert_equal 1, @work_item.work_item_handoffs.count
    assert service(handoff: handoff).cancel(reviewer: "reviewer").ok
    assert_equal "reviewer", @work_item.events.find_by!(event_type: "handoff.cancelled").actor
    assert service.prepare(prepared_by: "other operator").ok
    assert_empty @http.requests
  end

  private

  def service(**options)
    WorkItemHandoffService.new(work_item: @work_item, settings: @settings, url_policy: @policy, **options)
  end

  def enable_connection
    @settings.merge!(
      WorkItemHandoffService::ENABLED_SETTING => "true",
      WorkItemHandoffService::URL_SETTING => "https://handoff.example.org/work"
    )
  end

  def prepare_live
    enable_connection
    result = service.prepare(prepared_by: "operator")
    assert result.ok, result.error
    result.handoff
  end

  def approve_live
    handoff = prepare_live
    result = service(handoff: handoff).approve(reviewer: "operator")
    assert result.ok, result.error
    handoff
  end

  def http_response(code: "200", body: '{"receipt":"WORK-42"}')
    response_class = Net::HTTPResponse::CODE_TO_OBJ.fetch(code)
    response = response_class.new("1.1", code, "Test response")
    response.define_singleton_method(:body) { body }
    response
  end
end
