module Admin
  class AgentSettingsController < BaseController
    before_action :load_agent_setting, only: [ :show, :edit, :update, :destroy, :sync_from, :push_to ]
    before_action :load_twilio_numbers, only: [ :new, :edit ]

    def index
      @agent_settings = AgentSetting.order(:name, :agent_id)
      load_twilio_numbers
    rescue StandardError
      @twilio_numbers = []
      @twilio_error = "Unable to load Twilio phone numbers."
    end

    def new
      @agent_setting = AgentSetting.new
    end

    def create
      @agent_setting = AgentSetting.new(normalized_agent_setting_params)

      if @agent_setting.save
        twilio_error = sync_twilio_number(@agent_setting)
        flash[:alert] = twilio_error if twilio_error.present?
        redirect_to admin_agent_setting_path(@agent_setting), notice: "Agent created."
      else
        load_twilio_numbers
        render :new, status: :unprocessable_entity
      end
    end

    def show; end

    def edit; end

    def update
      if @agent_setting.update(normalized_agent_setting_params)
        twilio_error = sync_twilio_number(@agent_setting)
        flash[:alert] = twilio_error if twilio_error.present?
        redirect_to admin_agent_setting_path(@agent_setting), notice: "Agent settings updated."
      else
        load_twilio_numbers
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @agent_setting.destroy
      redirect_to admin_agent_settings_path, notice: "Agent deleted."
    end

    def sync_from
      redirect_to admin_agent_setting_path(@agent_setting), notice: "OpenAI Realtime profiles are configured locally."
    end

    def push_to
      redirect_to admin_agent_setting_path(@agent_setting), notice: "OpenAI Realtime uses this local profile on the next call."
    end

    def sync_all
      redirect_to admin_agent_settings_path, notice: "OpenAI Realtime profiles are configured locally."
    end

    private

    def load_agent_setting
      @agent_setting = AgentSetting.find(params[:id])
    end

    def agent_setting_params
      params.require(:agent_setting).permit(
        :agent_id,
        :name,
        :first_message,
        :system_prompt,
        :twilio_number,
        :voice_id,
        :tool_url,
        :tools_json
      )
    end

    def normalized_agent_setting_params
      attributes = agent_setting_params
      tools_json = attributes.delete(:tools_json)
      attributes[:tools] = parse_tools(tools_json) if tools_json.present?
      attributes
    end

    def parse_tools(tools_json)
      JSON.parse(tools_json)
    rescue JSON::ParserError
      []
    end

    def load_twilio_numbers
      @twilio_numbers = []
      @twilio_number_options = []
      @twilio_error = nil
      imported_voicebot_number = AppSetting.fetch("VOICEBOT_TWILIO_FROM_NUMBER").to_s.strip
      account_sid = AppSetting.fetch("TWILIO_ACCOUNT_SID")
      auth_token = AppSetting.fetch("TWILIO_AUTH_TOKEN")
      if account_sid.blank? || auth_token.blank?
        if imported_voicebot_number.present?
          formatted = ApplicationController.helpers.format_phone(imported_voicebot_number)
          @twilio_number_options = [ [ "#{formatted} · Imported from OpenAI Realtime", imported_voicebot_number ] ]
          @twilio_error = "Missing TWILIO_ACCOUNT_SID or TWILIO_AUTH_TOKEN. You can still attach the imported Realtime number, but Athena will not be able to update Twilio webhooks until credentials are added."
        else
          @twilio_error = "Missing TWILIO_ACCOUNT_SID or TWILIO_AUTH_TOKEN."
        end
        return
      end

      client = Twilio::REST::Client.new(account_sid, auth_token)
      numbers = client.incoming_phone_numbers.list(limit: 200)
      agent_by_number = AgentSetting.where.not(twilio_number: nil).index_by { |setting| normalize_phone(setting.twilio_number) }

      @twilio_numbers = numbers.map do |number|
        phone = number.phone_number
        normalized = normalize_phone(phone)
        mapped_agent = agent_by_number[normalized]
        {
          phone_number: phone,
          friendly_name: number.friendly_name,
          agent_name: mapped_agent&.name,
          agent_id: mapped_agent&.agent_id
        }
      end
      @twilio_number_options = numbers.map do |number|
        formatted = ApplicationController.helpers.format_phone(number.phone_number)
        label = [ formatted, number.friendly_name.presence ].compact.join(" · ")
        [ label, number.phone_number ]
      end
    rescue StandardError => error
      @twilio_numbers = []
      @twilio_number_options = []
      @twilio_error = error.message
    end

    def normalize_phone(value)
      value.to_s.gsub(/[^\d\+]/, "").presence
    end

    def sync_twilio_number(agent_setting)
      return if agent_setting.twilio_number.blank?

      account_sid = AppSetting.fetch("TWILIO_ACCOUNT_SID")
      auth_token = AppSetting.fetch("TWILIO_AUTH_TOKEN")
      if account_sid.blank? || auth_token.blank?
        imported_voicebot_number = AppSetting.fetch("VOICEBOT_TWILIO_FROM_NUMBER").to_s.strip
        if normalize_phone(imported_voicebot_number) == normalize_phone(agent_setting.twilio_number)
          return "Attached the imported Realtime number, but Athena could not update Twilio webhooks because credentials are missing."
        end

        return "Twilio credentials are missing, so the phone number could not be updated."
      end

      client = Twilio::REST::Client.new(account_sid, auth_token)
      phone = agent_setting.twilio_number
      incoming = client.incoming_phone_numbers.list(phone_number: phone).first
      if incoming.blank?
        normalized = normalize_phone(phone)
        incoming = client.incoming_phone_numbers.list(limit: 200).find do |record|
          normalize_phone(record.phone_number) == normalized
        end
      end
      return "Twilio phone number #{phone} was not found." if incoming.blank?

      inbound_url = public_twilio_inbound_url
      status_url = public_twilio_status_url
      incoming.update(
        voice_url: inbound_url,
        voice_method: "POST",
        status_callback: status_url,
        status_callback_method: "POST"
      )
      nil
    rescue StandardError => error
      "Twilio update failed: #{error.message}"
    end

    def public_twilio_inbound_url
      build_public_url("/voice/inbound")
    end

    def public_twilio_status_url
      build_public_url("/voice/outbound/status")
    end

    def build_public_url(path)
      base_url = AppSetting.fetch("PUBLIC_BASE_URL").presence
      return request.base_url + path if base_url.blank?

      URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", path.delete_prefix("/")).to_s
    end
  end
end
