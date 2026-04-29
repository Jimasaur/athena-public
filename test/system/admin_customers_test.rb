require "application_system_test_case"

class AdminCustomersTest < ApplicationSystemTestCase
  test "view customers list" do
    visit admin_customers_path

    assert_text "Contacts"
    assert_text customers(:one).name
  end

  test "view customer detail" do
    customer = customers(:one)

    visit admin_customer_path(customer)

    assert_text "Patient details"
    assert_text "+1 (415) 555-0100"
  end
end
