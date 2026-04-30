module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin!
    after_action :write_admin_cable_cookie

    private

    def authenticate_admin!
      return mark_admin_authenticated! if proxy_authenticated?

      username = AppSetting.fetch("ADMIN_USERNAME").to_s
      password = AppSetting.fetch("ADMIN_PASSWORD").to_s
      return mark_admin_authenticated! if username.blank? && password.blank? && !admin_auth_required?
      return request_http_basic_authentication("Athena Admin") if username.blank? || password.blank?

      authenticated = authenticate_or_request_with_http_basic("Athena Admin") do |provided_username, provided_password|
        secure_compare(provided_username, username) && secure_compare(provided_password, password)
      end
      mark_admin_authenticated! if authenticated
    end

    def admin_auth_required?
      Rails.env.production? ||
        public_surface_configured? ||
        truthy_setting?("ATHENA_PUBLIC_DEMO_MODE") ||
        truthy_setting?("ADMIN_AUTH_REQUIRED")
    end

    def public_surface_configured?
      return false if Rails.env.test?

      AppSetting.fetch("PUBLIC_BASE_URL").to_s.strip.present? ||
        ENV["PUBLIC_BASE_URL"].to_s.strip.present?
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

    def mark_admin_authenticated!
      @admin_authenticated_for_cable = true
    end

    def write_admin_cable_cookie
      return unless @admin_authenticated_for_cable
      return if response.status == 401

      LiveAudioAuthorization.write_admin_cookie(cookies)
    end

    def secure_compare(provided, expected)
      return false if provided.blank? || expected.blank?
      return false unless provided.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end
