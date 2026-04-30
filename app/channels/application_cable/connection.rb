module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :admin_cable_session

    def connect
      reject_unauthorized_connection unless LiveAudioAuthorization.valid_admin_cookie?(cookies)

      self.admin_cable_session = true
    end
  end
end
