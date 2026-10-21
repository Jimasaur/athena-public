class WorkItemUpdateService
  EDITABLE_ATTRIBUTES = %w[title kind description next_step owner priority status due_on resolution_note].freeze

  def initialize(work_item:, attributes:, actor:)
    @work_item = work_item
    @attributes = attributes.to_h.stringify_keys
    @actor = actor
  end

  def call
    expected_version = submitted_lock_version
    unsupported = @attributes.keys - EDITABLE_ATTRIBUTES - [ "lock_version" ]
    if unsupported.any?
      @work_item.errors.add(:base, "Unsupported work item fields: #{unsupported.join(', ')}")
      raise ActiveRecord::RecordInvalid, @work_item
    end

    WorkItem.transaction do
      @work_item.reload
      raise_stale! unless @work_item.lock_version == expected_version

      @work_item.audit_actor = @actor
      @work_item.assign_attributes(@attributes.slice(*EDITABLE_ATTRIBUTES))
      @work_item.save! if @work_item.changed?
      @work_item
    end
  ensure
    @work_item.audit_actor = nil
  end

  private

  def submitted_lock_version
    raw = @attributes["lock_version"].to_s
    raise_stale! unless raw.match?(/\A\d+\z/)

    raw.to_i
  end

  def raise_stale!
    raise ActiveRecord::StaleObjectError.new(@work_item, "update")
  end
end
