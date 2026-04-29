class SidecarEvent < ApplicationRecord
  belongs_to :call_state
  belongs_to :conversation

  validates :source, :kind, :occurred_at, presence: true
end
