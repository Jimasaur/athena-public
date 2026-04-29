class Conversation < ApplicationRecord
  belongs_to :customer
  belongs_to :transcript_call_event, class_name: "CallEvent", optional: true

  has_many :messages, dependent: :destroy
  has_many :call_events, dependent: :destroy
  has_one :call_state, dependent: :destroy
  has_many :sidecar_events, dependent: :destroy
  has_many :action_drafts, dependent: :destroy
  has_many :idea_captures, dependent: :destroy
  has_one_attached :recording

  validates :channel, :status, presence: true

  after_create_commit :broadcast_created
  after_create_commit :notify_discord
  after_update_commit :broadcast_updated
  before_destroy :clear_transcript_call_event

  private

  def clear_transcript_call_event
    return if transcript_call_event_id.blank?

    update_column(:transcript_call_event_id, nil)
  end

  def broadcast_created
    broadcast_prepend_to(
      "conversations",
      target: "conversations",
      partial: "admin/conversations/conversation",
      locals: { conversation: self }
    )
  end

  def broadcast_updated
    broadcast_replace_to(
      "conversations",
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "admin/conversations/conversation",
      locals: { conversation: self }
    )
  end

  def notify_discord
    ConversationDiscordNotificationService.new(conversation: self).call
  end
end
