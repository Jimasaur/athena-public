class Customer < ApplicationRecord
  has_many :conversations, dependent: :destroy

  validates :phone_number, presence: true
end
