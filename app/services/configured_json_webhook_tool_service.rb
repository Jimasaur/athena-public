require "net/http"
require "json"

class ConfiguredJsonWebhookToolService
  def initialize(setting_key:, payload:)
    @setting_key = setting_key
    @payload = payload
  end

  def call
    url = AppSetting.fetch(@setting_key).to_s.strip
    return unavailable("Missing #{@setting_key}.", status: :service_unavailable) if url.blank?

    uri = connector_uri(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    bearer_token = AppSetting.fetch("#{@setting_key}_BEARER").to_s.strip
    request["Authorization"] = "Bearer #{bearer_token}" if bearer_token.present?
    request.body = JSON.generate(@payload)

    response = http.request(request)
    payload = parse_json(response.body)
    unless response.is_a?(Net::HTTPSuccess)
      return unavailable(
        payload["error"] || "#{@setting_key} returned status #{response.code}.",
        status: :bad_gateway
      )
    end

    {
      ok: true,
      provider: @setting_key,
      response: payload
    }
  rescue URI::InvalidURIError
    unavailable("Invalid URL configured for #{@setting_key}.", status: :unprocessable_entity)
  rescue StandardError => error
    unavailable("Connector failed: #{error.message}", status: :bad_gateway)
  end

  private

  def connector_uri(url)
    uri = URI.parse(url)
    unless uri.is_a?(URI::HTTP) && uri.host.present?
      raise URI::InvalidURIError, "URL must be HTTP or HTTPS"
    end

    uri
  end

  def parse_json(body)
    return {} if body.to_s.strip.blank?

    JSON.parse(body)
  rescue JSON::ParserError
    { "raw_body" => body.to_s }
  end

  def unavailable(message, status: :unprocessable_entity)
    {
      ok: false,
      error: message,
      status: Rack::Utils.status_code(status)
    }
  end
end
