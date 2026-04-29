class TranscriptRoleNormalizer
  ASSISTANT_VALUES = %w[
    agent
    ai
    assistant
    bot
    llm
    outbound
    outbound_track
    response
    agent_response
    assistant_response
    voice_agent
    virtual_agent
  ].freeze

  USER_VALUES = %w[
    caller
    client
    customer
    human
    inbound
    inbound_track
    patient
    user
  ].freeze

  class << self
    def call(value, default: "user")
      normalized = normalize(value)
      return "assistant" if ASSISTANT_VALUES.include?(normalized)
      return "user" if USER_VALUES.include?(normalized)

      default
    end

    def from_entry(entry, default: "user")
      return default unless entry.respond_to?(:[])

      call(
        entry["role"] ||
          entry[:role] ||
          entry["speaker"] ||
          entry[:speaker] ||
          entry["speaker_type"] ||
          entry[:speaker_type] ||
          entry["sender"] ||
          entry[:sender] ||
          entry["source"] ||
          entry[:source] ||
          entry["participant"] ||
          entry[:participant] ||
          entry["participant_type"] ||
          entry[:participant_type] ||
          entry["track"] ||
          entry[:track],
        default: default
      )
    end

    private

    def normalize(value)
      value.to_s
        .downcase
        .strip
        .tr("-", "_")
        .gsub(/\s+/, "_")
    end
  end
end
