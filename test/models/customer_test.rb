require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires phone number" do
    customer = Customer.new(name: "Test Caller")

    assert_not customer.valid?
    assert_includes customer.errors[:phone_number], "can't be blank"
  end
end
