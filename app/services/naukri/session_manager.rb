# app/services/naukri/session_manager.rb
module Naukri
  class SessionManager
    SESSION_FILE = Rails.root.join("tmp", "session.json").to_s

    def self.save_session(auth_service)
      session_data = {
        token: auth_service.token,
        cookies: auth_service.cookies,
        user_info: auth_service.user_info,
        # profile_id: auth_service.profile_id,
        created_at: Time.current.iso8601,
        expires_at: extract_expiry(auth_service.token)
      }

      FileUtils.mkdir_p(File.dirname(SESSION_FILE))
      File.write(SESSION_FILE, JSON.pretty_generate(session_data))
      
      Rails.logger.info "[SessionManager] ✅ Session saved to #{SESSION_FILE}"
      session_data
    end

    def self.load_session
      return nil unless File.exist?(SESSION_FILE)

      session_data = JSON.parse(File.read(SESSION_FILE))
      
      # Check if session is expired
      if session_data["expires_at"]
        expires_at = Time.parse(session_data["expires_at"])
        if expires_at < Time.current
          Rails.logger.warn "[SessionManager] ⚠️  Session expired"
          delete_session
          return nil
        end
      end

      Rails.logger.info "[SessionManager] ✅ Session loaded"
      session_data
    end

    def self.session_valid?
      session = load_session
      session.present?
    end

    def self.delete_session
      File.delete(SESSION_FILE) if File.exist?(SESSION_FILE)
      Rails.logger.info "[SessionManager] Session deleted"
    end

    def self.session_status
      return { status: "no_session" } unless File.exist?(SESSION_FILE)

      session = JSON.parse(File.read(SESSION_FILE))
      expires_at = Time.parse(session["expires_at"])
      hours_left = ((expires_at - Time.current) / 3600).round(1)

      if expires_at < Time.current
        { status: "expired" }
      elsif hours_left < 1
        { status: "expiring_soon", hours_left: hours_left }
      else
        { status: "valid", hours_left: hours_left, email: session.dig("user_info", "username") }
      end
    end

    private

    def self.extract_expiry(token)
      return nil if token.blank?

      begin
        payload = JWT.decode(token, nil, false)[0]
        Time.at(payload["exp"]).iso8601
      rescue
        (Time.current + 24.hours).iso8601
      end
    end
  end
end
