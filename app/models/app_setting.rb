class AppSetting < ApplicationRecord
  KEY_FORMAT = /\A[A-Z0-9_]+\z/

  validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT }

  before_validation :normalize_key!

  scope :ordered, -> { order(:key) }

  def self.fetch(key, default = nil)
    normalized_key = normalize_key(key)

    database_value = find_by(key: normalized_key)&.value
    return database_value unless database_value.nil?

    environment_value = ENV[normalized_key]
    return environment_value unless environment_value.nil?

    return yield if block_given?

    default
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    ENV[normalized_key] || default
  end

  def self.[](key)
    fetch(key)
  end

  def self.normalize_key(key)
    key.to_s.strip.upcase
  end

  private

  def normalize_key!
    self.key = self.class.normalize_key(key)
  end
end
