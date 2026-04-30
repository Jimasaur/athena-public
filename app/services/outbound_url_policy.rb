require "ipaddr"
require "net/http"
require "resolv"
require "set"
require "uri"

class OutboundUrlPolicy
  Result = Struct.new(:ok, :uri, :ipaddr, :error, keyword_init: true) do
    def ok?
      ok
    end
  end

  DISCORD_WEBHOOK_HOSTS = %w[discord.com discordapp.com].freeze
  DISCORD_WEBHOOK_PATH = %r{\A/api/webhooks/}i
  LOCAL_ALLOWLIST_SETTING = "ATHENA_OUTBOUND_LOCAL_URL_ALLOWLIST"
  BLOCKED_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.0.2.0/24"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("198.18.0.0/15"),
    IPAddr.new("198.51.100.0/24"),
    IPAddr.new("203.0.113.0/24"),
    IPAddr.new("224.0.0.0/4"),
    IPAddr.new("240.0.0.0/4"),
    IPAddr.new("::/128"),
    IPAddr.new("::1/128"),
    IPAddr.new("::ffff:0:0/96"),
    IPAddr.new("64:ff9b::/96"),
    IPAddr.new("100::/64"),
    IPAddr.new("2001:db8::/32"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10"),
    IPAddr.new("ff00::/8")
  ].freeze
  INTERNAL_BLOCKED_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("224.0.0.0/4"),
    IPAddr.new("240.0.0.0/4"),
    IPAddr.new("::/128"),
    IPAddr.new("100::/64"),
    IPAddr.new("2001:db8::/32"),
    IPAddr.new("fe80::/10"),
    IPAddr.new("ff00::/8")
  ].freeze

  class << self
    def external(url, require_discord: false)
      validate(url, allow_private: local_allowlisted?(url), require_discord: require_discord)
    end

    def internal_callback(url)
      validate(url, allow_private: true, internal: true)
    end

    def prepare_http(uri, ipaddr)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.ipaddr = ipaddr.to_s if ipaddr
        http.use_ssl = uri.scheme == "https"
      end
    end

    def local_allowlisted?(url)
      uri = parse_uri(url)
      return false unless uri

      allowed_origins.include?(origin_for(uri))
    end

    private

    def validate(url, allow_private:, require_discord: false, internal: false)
      uri = parse_uri(url)
      return failure("URL must be HTTP or HTTPS.") unless uri&.is_a?(URI::HTTP)
      return failure("URL host is required.") if uri.host.blank?
      return failure("URL userinfo is not allowed.") if uri.userinfo.present?
      return failure("URL fragments are not allowed.") if uri.fragment.present?
      if require_discord && !discord_webhook?(uri) && !local_allowlisted?(url)
        return failure("Discord webhook URL must use discord.com or discordapp.com.")
      end

      addresses = resolve_addresses(uri.host)
      return failure("URL host did not resolve.") if addresses.blank?

      blocked_ranges = internal ? INTERNAL_BLOCKED_RANGES : BLOCKED_RANGES
      unsafe = addresses.find { |address| unsafe_address?(address, blocked_ranges) }
      if unsafe && (!allow_private || internal)
        return failure("URL resolves to a private or reserved network.")
      end

      Result.new(ok: true, uri: uri, ipaddr: addresses.first)
    rescue URI::InvalidURIError
      failure("Invalid URL.")
    rescue Resolv::ResolvError
      failure("URL host did not resolve.")
    end

    def parse_uri(url)
      URI.parse(url.to_s.strip)
    rescue URI::InvalidURIError
      nil
    end

    def origin_for(uri)
      port = uri.port
      default_port = uri.default_port
      host = uri.host.to_s.downcase
      "#{uri.scheme}://#{host}#{port == default_port ? "" : ":#{port}"}"
    end

    def allowed_origins
      AppSetting.fetch(LOCAL_ALLOWLIST_SETTING).to_s.split(/[,\s]+/).filter_map do |url|
        uri = parse_uri(url)
        origin_for(uri) if uri&.is_a?(URI::HTTP) && uri.host.present?
      end.to_set
    end

    def discord_webhook?(uri)
      uri.scheme == "https" &&
        DISCORD_WEBHOOK_HOSTS.include?(uri.host.to_s.downcase) &&
        uri.path.match?(DISCORD_WEBHOOK_PATH)
    end

    def resolve_addresses(host)
      Resolv.getaddresses(host).map { |address| IPAddr.new(address) }
    end

    def unsafe_address?(address, ranges)
      ranges.any? { |range| range.include?(address) }
    end

    def failure(error)
      Result.new(ok: false, error: error)
    end
  end
end
