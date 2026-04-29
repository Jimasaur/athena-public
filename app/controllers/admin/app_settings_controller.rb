module Admin
  class AppSettingsController < BaseController
    REALTIME_SETTING_DEFINITIONS = [
      {
        key: "OPENAI_API_KEY",
        label: "API key",
        input: "password",
        secret: true,
        placeholder: "Stored; enter a replacement key"
      },
      {
        key: "OPENAI_REALTIME_MODEL",
        label: "Model",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_MODEL,
        placeholder: OpenaiRealtimeTwilioBridge::DEFAULT_MODEL
      },
      {
        key: "OPENAI_REALTIME_VOICE",
        label: "Voice",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_VOICE,
        placeholder: OpenaiRealtimeTwilioBridge::DEFAULT_VOICE
      },
      {
        key: "OPENAI_REALTIME_TRANSCRIPTION_MODEL",
        label: "Input transcription model",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_TRANSCRIPTION_MODEL,
        placeholder: OpenaiRealtimeTwilioBridge::DEFAULT_TRANSCRIPTION_MODEL
      },
      {
        key: "OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED",
        label: "Twilio transcript mirror",
        input: "boolean",
        default: false
      },
      {
        key: "OPENAI_REALTIME_INPUT_NOISE_REDUCTION",
        label: "Input noise reduction",
        input: "select",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_INPUT_NOISE_REDUCTION,
        options: [ "near_field", "far_field", "none" ]
      },
      {
        key: "OPENAI_REALTIME_TURN_DETECTION_TYPE",
        label: "Turn detection",
        input: "select",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_TURN_DETECTION_TYPE,
        options: [ "server_vad", "semantic_vad", "none" ]
      },
      {
        key: "OPENAI_REALTIME_VAD_THRESHOLD",
        label: "VAD threshold",
        input: "number",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_VAD_THRESHOLD,
        min: 0,
        max: 1,
        step: 0.05
      },
      {
        key: "OPENAI_REALTIME_VAD_PREFIX_PADDING_MS",
        label: "VAD prefix padding",
        input: "number",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_VAD_PREFIX_PADDING_MS,
        min: 0,
        step: 50,
        suffix: "ms"
      },
      {
        key: "OPENAI_REALTIME_VAD_SILENCE_DURATION_MS",
        label: "VAD silence duration",
        input: "number",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_VAD_SILENCE_DURATION_MS,
        min: 0,
        step: 50,
        suffix: "ms"
      },
      {
        key: "OPENAI_REALTIME_VAD_IDLE_TIMEOUT_MS",
        label: "VAD idle timeout",
        input: "number",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_VAD_IDLE_TIMEOUT_MS,
        min: 0,
        step: 500,
        suffix: "ms"
      },
      {
        key: "OPENAI_REALTIME_SEMANTIC_EAGERNESS",
        label: "Semantic VAD eagerness",
        input: "select",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_SEMANTIC_EAGERNESS,
        options: [ "auto", "low", "medium", "high" ]
      },
      {
        key: "OPENAI_REALTIME_CREATE_RESPONSE",
        label: "Auto-create response",
        input: "boolean",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_CREATE_RESPONSE
      },
      {
        key: "OPENAI_REALTIME_INTERRUPT_RESPONSE",
        label: "Allow barge-in interruption",
        input: "boolean",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_INTERRUPT_RESPONSE
      },
      {
        key: "OPENAI_REALTIME_INTERRUPT_GRACE_MS",
        label: "Opening interrupt grace",
        input: "number",
        default: OpenaiRealtimeTwilioBridge::DEFAULT_INTERRUPT_GRACE_MS,
        min: 0,
        step: 250,
        suffix: "ms"
      },
      {
        key: "OPENAI_REALTIME_SESSION_OVERRIDES_JSON",
        label: "Advanced session overrides",
        input: "textarea",
        placeholder: "{\"audio\":{\"input\":{\"turn_detection\":{\"threshold\":0.7}}}}"
      }
    ].freeze

    before_action :load_app_setting, only: [ :edit, :update, :destroy ]

    def index
      @app_settings = AppSetting.ordered
      @new_app_setting = AppSetting.new
      @realtime_settings = realtime_settings
    end

    def new
      @app_setting = AppSetting.new
    end

    def create
      @app_setting = AppSetting.new(app_setting_params)
      if @app_setting.save
        redirect_to admin_app_settings_path, notice: "Config variable created."
      else
        redirect_to admin_app_settings_path, alert: @app_setting.errors.full_messages.to_sentence
      end
    end

    def edit; end

    def update
      if @app_setting.update(app_setting_params)
        redirect_to admin_app_settings_path, notice: "Config variable updated."
      else
        redirect_to admin_app_settings_path, alert: @app_setting.errors.full_messages.to_sentence
      end
    end

    def realtime
      submitted = params.fetch(:realtime, {})
      submitted = submitted.to_unsafe_h if submitted.respond_to?(:to_unsafe_h)

      REALTIME_SETTING_DEFINITIONS.each do |definition|
        key = definition.fetch(:key)
        next unless submitted.key?(key)

        value = submitted[key].to_s
        next if definition[:secret] && value.blank?

        setting = AppSetting.find_or_initialize_by(key: key)
        setting.value = value
        setting.save!
      end

      redirect_to admin_app_settings_path, notice: "OpenAI Realtime settings updated."
    end

    def destroy
      @app_setting.destroy
      redirect_to admin_app_settings_path, notice: "Config variable deleted."
    end

    private

    def load_app_setting
      @app_setting = AppSetting.find(params[:id])
    end

    def app_setting_params
      params.require(:app_setting).permit(:key, :value)
    end

    def realtime_settings
      REALTIME_SETTING_DEFINITIONS.map do |definition|
        value = AppSetting.find_by(key: definition.fetch(:key))&.value
        definition.merge(value: value, present: value.present?)
      end
    end
  end
end
