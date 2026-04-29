module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin_if_configured

    private

    def authenticate_admin_if_configured
      username = AppSetting.fetch("ADMIN_USERNAME").to_s
      password = AppSetting.fetch("ADMIN_PASSWORD").to_s
      return if username.blank? && password.blank?

      authenticate_or_request_with_http_basic("Athena Admin") do |provided_username, provided_password|
        secure_compare(provided_username, username) && secure_compare(provided_password, password)
      end
    end

    def secure_compare(provided, expected)
      return false if provided.blank? || expected.blank?
      return false unless provided.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end
