# app/services/naukri/profile_service.rb
require "faraday"

module Naukri
  class ProfileService
    CONFIG = Rails.application.config_for(:naukri).freeze

    PROFILE_API_URL = "https://www.naukri.com/profile-services/v1/user/profile".freeze

    def initialize(auth_service)
      @auth   = auth_service
      @logger = Rails.logger
    end

    # Fetch current profile details
    def fetch_profile
      @logger.info "[Naukri::ProfileService] Fetching profile..."

      return Result.failure("Not authenticated") unless @auth.logged_in?

      response = connection.get(PROFILE_API_URL) do |req|
        req.headers.merge!(@auth.auth_headers)
      end

      if response.success?
        data = parse_body(response.body)
        @logger.info "[Naukri::ProfileService] ✅ Profile fetched"
        Result.success(profile: data)
      else
        @logger.error "[Naukri::ProfileService] ❌ Failed to fetch profile [#{response.status}]"
        Result.failure("Failed to fetch profile: #{response.status}")
      end
    end

    # Refresh profile to boost visibility
    def refresh_profile
      @logger.info "[Naukri::ProfileService] Refreshing profile activity..."

      return Result.failure("Not authenticated") unless @auth.logged_in?

      result = fetch_profile
      if result.success?
        @logger.info "[Naukri::ProfileService] ✅ Profile refreshed successfully"
        Result.success(message: "Profile refreshed", refreshed_at: Time.current.iso8601)
      else
        result
      end
    end

    private

    def connection
      @connection ||= Faraday.new do |f|
        f.options.timeout      = 30
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end

    def parse_body(body)
      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end
  end
end
