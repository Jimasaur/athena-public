class AddCustomerPortraitToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :customer_portrait, :text
  end
end
