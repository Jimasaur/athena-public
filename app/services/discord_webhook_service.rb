require "net/http"
require "json"

class DiscordWebhookService
  def initialize(url:, username: nil)
    @url = url.to_s.strip
    @username = username.to_s.strip
  end

  def post(content:, embeds: nil)
    return { ok: false, error: "Discord webhook URL is missing." } if @url.blank?

    policy = OutboundUrlPolicy.external(@url, require_discord: true)
    return { ok: false, error: policy.error, status: 422 } unless policy.ok?

    uri = policy.uri
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      {
        content: content,
        username: @username.presence,
        embeds: embeds
      }.compact
    )

    http = OutboundUrlPolicy.prepare_http(uri, policy.ipaddr)
    http.open_timeout = 5
    http.read_timeout = 10
    response = http.request(request)

    return { ok: true, status: response.code.to_i } if response.is_a?(Net::HTTPSuccess) || response.code.to_i == 204

    { ok: false, error: "Discord webhook returned #{response.code}.", status: response.code.to_i }
  rescue StandardError => error
    { ok: false, error: error.message }
  end
end
