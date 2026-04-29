class CustomerLookupService
  def initialize(phone_number:)
    @phone_number = phone_number
  end

  def call
    return if @phone_number.blank?

    Customer.find_by(phone_number: @phone_number)
  end
end
