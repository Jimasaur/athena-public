class RemoveOptInFromCustomers < ActiveRecord::Migration[8.1]
  def change
    remove_column :customers, :opt_in, :boolean, null: false, default: true
  end
end
