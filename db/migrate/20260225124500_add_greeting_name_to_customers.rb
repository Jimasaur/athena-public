class AddGreetingNameToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :greeting_name, :string
  end
end
