class CustomerUpdateService
  def initialize(customer:, attributes:)
    @customer = customer
    @attributes = attributes
  end

  def call
    update_attrs = @attributes.slice(:name)
    update_metadata = @attributes[:metadata]
    update_metadata = update_metadata.to_unsafe_h if update_metadata.respond_to?(:to_unsafe_h)

    if update_metadata.is_a?(Hash)
      update_attrs[:metadata] = @customer.metadata.merge(update_metadata.compact)
    end

    @customer.update(update_attrs)
  end
end
