require "test_helper"

module Admin
  class OutboundCallsControllerTest < ActionDispatch::IntegrationTest
    test "creates outbound call for patient" do
      agent_setting = agent_settings(:one)
      customer = customers(:one)

      fake_calls = Class.new do
        attr_reader :last_params

        def create(params)
          @last_params = params
          Struct.new(:sid).new("CA123")
        end
      end.new

      fake_client = Struct.new(:calls).new(fake_calls)

      original_new = Twilio::REST::Client.method(:new)
      Twilio::REST::Client.define_singleton_method(:new) { |_sid, _token| fake_client }

      begin
        post admin_outbound_calls_path, params: {
          agent_setting_id: agent_setting.id,
          patient_id: customer.id
        }
      ensure
        Twilio::REST::Client.define_singleton_method(:new) do |*args, &block|
          original_new.call(*args, &block)
        end
      end

      assert_response :redirect
      assert_equal agent_setting.twilio_number, fake_calls.last_params[:from]
      assert_equal customer.phone_number, fake_calls.last_params[:to]
      assert_equal "POST", fake_calls.last_params[:method]
      assert_includes fake_calls.last_params[:url], twilio_outbound_path
      assert_includes fake_calls.last_params[:status_callback], twilio_status_webhook_path
    end

    test "requires agent and destination phone" do
      post admin_outbound_calls_path

      assert_response :redirect
      assert_equal "Select an agent to place the call.", flash[:alert]
    end
  end
end
