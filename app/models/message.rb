class Message < ApplicationRecord
  belongs_to :conversation

  validates :role, :content, :sent_at, presence: true

  after_create_commit :broadcast_created

  private

  def broadcast_created
    broadcast_append_to(
      conversation,
      target: ActionView::RecordIdentifier.dom_id(conversation, :messages),
      partial: "admin/conversations/message",
      locals: { message: self }
    )
  end
end
