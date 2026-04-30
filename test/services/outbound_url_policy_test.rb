require "test_helper"

class OutboundUrlPolicyTest < ActiveSupport::TestCase
  test "allows public https URL" do
    with_resolver("example.com" => [ "93.184.216.34" ]) do
      result = OutboundUrlPolicy.external("https://example.com/hook")

      assert result.ok?
      assert_equal "example.com", result.uri.host
    end
  end

  test "rejects loopback by default" do
    with_resolver("localhost" => [ "127.0.0.1" ]) do
      result = OutboundUrlPolicy.external("http://localhost:3000/hook")

      assert_not result.ok?
      assert_includes result.error, "private or reserved"
    end
  end

  test "allows exact local origin when allowlisted" do
    AppSetting.create!(key: "ATHENA_OUTBOUND_LOCAL_URL_ALLOWLIST", value: "http://localhost:3000")

    with_resolver("localhost" => [ "127.0.0.1" ]) do
      result = OutboundUrlPolicy.external("http://localhost:3000/hook")

      assert result.ok?
    end
  end

  test "requires Discord webhook host in Discord mode" do
    with_resolver(
      "example.com" => [ "93.184.216.34" ],
      "discord.com" => [ "162.159.135.234" ]
    ) do
      rejected = OutboundUrlPolicy.external("https://example.com/api/webhooks/1/2", require_discord: true)
      accepted = OutboundUrlPolicy.external("https://discord.com/api/webhooks/1/2", require_discord: true)

      assert_not rejected.ok?
      assert accepted.ok?
    end
  end

  test "internal callback allows loopback but rejects metadata address" do
    with_resolver(
      "localhost" => [ "127.0.0.1" ],
      "metadata.test" => [ "169.254.169.254" ]
    ) do
      assert OutboundUrlPolicy.internal_callback("http://localhost:3002/agent_tools/command").ok?
      assert_not OutboundUrlPolicy.internal_callback("http://metadata.test/latest").ok?
    end
  end

  private

  def with_resolver(map)
    original = Resolv.method(:getaddresses)
    Resolv.define_singleton_method(:getaddresses) do |host|
      map.fetch(host) { raise Resolv::ResolvError, host }
    end
    yield
  ensure
    Resolv.define_singleton_method(:getaddresses) do |host|
      original.call(host)
    end
  end
end
