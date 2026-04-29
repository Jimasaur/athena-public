class IdeaCapture < ApplicationRecord
  STATUSES = %w[captured reported reviewed archived].freeze

  belongs_to :conversation

  validates :title, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  def caller_name
    conversation.customer&.name.presence || "Unknown caller"
  end
end
