module Admin
  class OutboundCallsController < BaseController
    def create
      agent_setting = AgentSetting.find_by(id: params[:agent_setting_id])
      return redirect_back_with_error("Select an agent to place the call.") if agent_setting.blank?

      customer = Customer.find_by(id: params[:patient_id]) if params[:patient_id].present?
      to_number = customer&.phone_number.presence || params[:phone_number].to_s
      return redirect_back_with_error("Enter a contact or phone number to call.") if to_number.blank?

      base_url = AppSetting.fetch("PUBLIC_BASE_URL").presence || request.base_url
      result = OutboundCallService.new(base_url: base_url).call(
        agent_setting: agent_setting,
        to_number: to_number
      )

      if result.error.present?
        redirect_back_with_error(result.error)
      else
        redirect_back fallback_location: admin_customers_path, notice: "Call initiated."
      end
    end

    private

    def redirect_back_with_error(message)
      redirect_back fallback_location: admin_customers_path, alert: message
    end
  end
end
