require "json"
require "securerandom"

class LiveAudioAuthorization
  ADMIN_COOKIE_NAME = :athena_admin_cable
  ADMIN_COOKIE_TTL = 4.hours
  LIVE_AUDIO_TOKEN_TTL = 90.minutes

  class << self
    def write_admin_cookie(cookies)
      cookies.signed[ADMIN_COOKIE_NAME] = {
        value: JSON.generate(
          issued_at: Time.current.to_i,
          nonce: SecureRandom.hex(16)
        ),
        expires: ADMIN_COOKIE_TTL.from_now,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?,
        path: "/cable"
      }
    end

    def valid_admin_cookie?(cookies)
      payload = parse_json(cookies.signed[ADMIN_COOKIE_NAME])
      issued_at = Time.zone.at(payload["issued_at"].to_i)
      issued_at.present? && issued_at >= ADMIN_COOKIE_TTL.ago
    rescue StandardError
      false
    end

    def token_for(conversation)
      return if conversation.blank? || conversation.status != "in_progress"

      verifier.generate(
        { conversation_id: conversation.id },
        purpose: :live_audio,
        expires_in: LIVE_AUDIO_TOKEN_TTL
      )
    end

    def conversation_id_from_token(token)
      payload = verifier.verified(token.to_s, purpose: :live_audio)
      payload&.with_indifferent_access&.dig(:conversation_id).to_i if payload
    end

    private

    def verifier
      Rails.application.message_verifier(:live_audio_authorization)
    end

    def parse_json(value)
      JSON.parse(value.to_s)
    end
  end
end
