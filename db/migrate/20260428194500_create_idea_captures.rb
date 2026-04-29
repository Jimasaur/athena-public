class CreateIdeaCaptures < ActiveRecord::Migration[7.1]
  def change
    create_table :idea_captures do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :title, null: false
      t.string :category
      t.string :department
      t.string :status, null: false, default: "captured"
      t.text :problem
      t.text :proposed_solution
      t.text :impact
      t.text :next_step
      t.json :payload, default: {}

      t.timestamps
    end

    add_index :idea_captures, :category
    add_index :idea_captures, :status
  end
end
