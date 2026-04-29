require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test

  def connect_turbo_cable_stream_sources
    return if Capybara.current_driver == :rack_test

    super
  end
end
