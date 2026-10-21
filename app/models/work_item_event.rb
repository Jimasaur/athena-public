class WorkItemEvent < ApplicationRecord
  belongs_to :work_item, inverse_of: :events

  validates :event_type, :actor, presence: true
  validates :event_type, length: { maximum: 80 }, format: { with: /\A[a-z][a-z0-9_.-]*\z/ }
  validates :actor, length: { maximum: 120 }
  validate :details_are_an_object

  private

  def details_are_an_object
    errors.add(:details, "must be an object") unless details.is_a?(Hash)
  end
end
