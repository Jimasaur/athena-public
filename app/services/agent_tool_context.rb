class AgentToolContext
  HEADER = "X-Athena-Tool-Context"
  TOKEN_TTL = 30.minutes

  class << self
    def token_for(conversation:, call_sid:)
      return if conversation.blank?

      verifier.generate(
        {
          conversation_id: conversation.id,
          call_sid: call_sid.to_s.presence || conversation.twilio_call_sid
        }.compact,
        purpose: :agent_tool_context,
        expires_in: TOKEN_TTL
      )
    end

    def verify(token)
      payload = verifier.verified(token.to_s, purpose: :agent_tool_context)
      return {} unless payload.is_a?(Hash)

      payload.with_indifferent_access
    rescue StandardError
      {}
    end

    private

    def verifier
      Rails.application.message_verifier(:agent_tool_context)
    end
  end
end
