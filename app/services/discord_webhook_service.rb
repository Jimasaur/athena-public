require "net/http"
require "json"

class DiscordWebhookService
  def initialize(url:, username: nil)
    @url = url.to_s.strip
    @username = username.to_s.strip
  end

  def post(content:, embeds: nil)
    return { ok: false, error: "Discord webhook URL is missing." } if @url.blank?

    uri = URI(@url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      {
        content: content,
        username: @username.presence,
        embeds: embeds
      }.compact
    )

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    response = http.request(request)

    return { ok: true, status: response.code.to_i } if response.is_a?(Net::HTTPSuccess) || response.code.to_i == 204

    { ok: false, error: "Discord webhook returned #{response.code}.", status: response.code.to_i }
  rescue StandardError => error
    { ok: false, error: error.message }
  end
end
