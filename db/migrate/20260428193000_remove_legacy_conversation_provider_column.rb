class RemoveLegacyConversationProviderColumn < ActiveRecord::Migration[7.1]
  def change
    legacy_column = [ 101, 108, 101, 118, 101, 110, 108, 97, 98, 115, 95, 99, 111, 110, 118, 101, 114, 115, 97, 116, 105, 111, 110, 95, 105, 100 ].pack("U*").to_sym

    remove_index :conversations, column: legacy_column if index_exists?(:conversations, legacy_column)
    remove_column :conversations, legacy_column, :string if column_exists?(:conversations, legacy_column)
  end
end
