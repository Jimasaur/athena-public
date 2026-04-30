require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "rejects missing admin cable cookie" do
    assert_reject_connection { connect }
  end

  test "accepts valid admin cable cookie" do
    LiveAudioAuthorization.write_admin_cookie(cookies)

    connect

    assert_equal true, connection.admin_cable_session
  end
end
