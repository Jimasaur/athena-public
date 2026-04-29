module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin!

    private

    def authenticate_admin!
      return if proxy_authenticated?

      username = AppSetting.fetch("ADMIN_USERNAME").to_s
      password = AppSetting.fetch("ADMIN_PASSWORD").to_s
      return if username.blank? && password.blank? && !admin_auth_required?
      return request_http_basic_authentication("Athena Admin") if username.blank? || password.blank?

      authenticate_or_request_with_http_basic("Athena Admin") do |provided_username, provided_password|
        secure_compare(provided_username, username) && secure_compare(provided_password, password)
      end
    end

    def admin_auth_required?
      Rails.env.production? ||
        truthy_setting?("ATHENA_PUBLIC_DEMO_MODE") ||
        truthy_setting?("ADMIN_AUTH_REQUIRED")
    end

    def proxy_authenticated?
      return false unless truthy_setting?("ATHENA_PUBLIC_DEMO_MODE")

      secret = AppSetting.fetch("ATHENA_PROXY_AUTH_SECRET").to_s
      provided = request.headers["X-Athena-Proxy-Secret"].to_s
      secure_compare(provided, secret)
    end

    def truthy_setting?(key)
      value = AppSetting.fetch(key)
      value = ENV[key] if value.nil?
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def secure_compare(provided, expected)
      return false if provided.blank? || expected.blank?
      return false unless provided.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end
