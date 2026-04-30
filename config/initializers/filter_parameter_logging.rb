# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw,
  :email,
  :secret,
  :token,
  :_key,
  :bearer,
  :webhook_url,
  :crypt,
  :salt,
  :certificate,
  :otp,
  :ssn,
  :cvv,
  :cvc,
  lambda do |key, value, original_params|
    next unless key.to_s == "value"
    next unless original_params.is_a?(Hash)

    setting_key = original_params.dig("app_setting", "key") || original_params.dig(:app_setting, :key)
    value.replace("[FILTERED]") if setting_key.present? && AppSetting.sensitive_key?(setting_key)
  end
]
