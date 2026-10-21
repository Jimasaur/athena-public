require "uri"

class WorkItemHandoff < ApplicationRecord
  STATUSES = %w[pending_approval approved delivering delivered failed unknown cancelled].freeze
  UNCERTAIN_STATUSES = %w[delivering unknown].freeze
  SNAPSHOT_FIELDS = %w[work_item_id payload payload_digest work_item_lock_version destination_url dry_run idempotency_key prepared_by].freeze

  belongs_to :work_item

  validates :payload, :payload_digest, :prepared_by, :idempotency_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :destination_url, presence: true, unless: :dry_run?
  validates :work_item_lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :snapshot_is_immutable, on: :update

  def delivery_uncertain?
    status.in?(UNCERTAIN_STATUSES)
  end

  def revision_current?
    work_item.lock_version == work_item_lock_version
  end

  def acknowledged?
    status == "delivered" && !dry_run?
  end

  def simulated?
    status == "delivered" && dry_run?
  end

  def destination_label
    return "Simulated handoff" if dry_run?

    uri = URI.parse(destination_url.to_s)
    "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? '' : ":#{uri.port}"}"
  rescue URI::InvalidURIError
    "Configured webhook"
  end

  private

  def snapshot_is_immutable
    SNAPSHOT_FIELDS.each do |field|
      errors.add(field, "cannot change after preparation") if will_save_change_to_attribute?(field)
    end
  end
end
