class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :phone_number, null: false
      t.string :name
      t.json :metadata, default: {}
      t.boolean :opt_in, null: false, default: true

      t.timestamps
    end

    add_index :customers, :phone_number
  end
end
