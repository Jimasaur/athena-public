require "net/http"
require "json"

class WebSearchService
  DEFAULT_MAX_RESULTS = 5

  def initialize(query:, max_results: nil, api_key: AppSetting.fetch("BRAVE_SEARCH_API_KEY"))
    @query = query.to_s.strip
    @max_results = normalize_max_results(max_results)
    @api_key = api_key.to_s.strip
  end

  def call
    return unavailable("Search query is required.") if @query.blank?
    return unavailable("BRAVE_SEARCH_API_KEY is missing.", status: :service_unavailable) if @api_key.blank?

    uri = URI("https://api.search.brave.com/res/v1/web/search")
    uri.query = URI.encode_www_form(q: @query, count: @max_results)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["X-Subscription-Token"] = @api_key

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      return unavailable("Search provider error (#{response.code}).", status: :bad_gateway)
    end

    body = JSON.parse(response.body)
    results = Array(body.dig("web", "results")).first(@max_results).map do |item|
      {
        title: item["title"],
        url: item["url"],
        description: item["description"],
        age: item["age"]
      }.compact
    end

    {
      ok: true,
      query: @query,
      provider: "brave_search",
      results: results
    }
  rescue JSON::ParserError
    unavailable("Search provider returned invalid JSON.", status: :bad_gateway)
  rescue StandardError => error
    unavailable("Search failed: #{error.message}", status: :bad_gateway)
  end

  private

  def normalize_max_results(value)
    parsed = value.to_i
    return DEFAULT_MAX_RESULTS if parsed <= 0

    [ parsed, 10 ].min
  end

  def unavailable(message, status: :unprocessable_entity)
    {
      ok: false,
      error: message,
      status: Rack::Utils.status_code(status)
    }
  end
end
