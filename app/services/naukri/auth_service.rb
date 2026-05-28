# app/services/naukri/auth_service.rb
require "faraday"
require "json"

module Naukri
  class AuthService
    attr_reader :token, :cookies, :user_info

    CONFIG = Rails.application.config_for(:naukri).freeze

    BASE_HEADERS = {
      "Content-Type" => "application/json",
      "Accept"       => "application/json",
      "appid"        => "105",
      "clientid"        => "d3skt0p",
      "systemid"     => "jobseeker",
      "User-Agent"   => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      "gid"          => "LOCATION,FIELD_DESIGNATION,INDUSTRY,SKILLS"
    }.freeze

    def initialize
      @token     = nil
      @cookies   = {}
      @user_info = {}
      @logger    = Rails.logger
    end

    # Perform login and store token + cookies
    def login
      @logger.info "[Naukri::AuthService] Attempting login for #{CONFIG[:email]}"

      validate_credentials!

      response = connection.post(CONFIG[:login_url]) do |req|
        req.headers.merge!(BASE_HEADERS)
        req.body = login_payload.to_json
      end

      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      @logger.error "[Naukri::AuthService] Connection failed: #{e.message}"
      Result.failure("Connection failed: #{e.message}")
    rescue Faraday::TimeoutError
      @logger.error "[Naukri::AuthService] Request timed out"
      Result.failure("Request timed out")
    end

    def logged_in?
      @token.present? || @cookies.any?
    end

    def cookie_string
      @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
    end

    def auth_headers
      BASE_HEADERS.merge(
        "Authorization" => "Bearer #{@token}",
        "Cookie"        => cookie_string
      ).compact
    end

    private

    def handle_response(response)
      if response.success?
        body = parse_body(response.body)
        extract_auth_data(response, body)
        @logger.info "[Naukri::AuthService] ✅ Login successful"
        Result.success(user_info: @user_info, token: @token)
      else
        @logger.error "[Naukri::AuthService] ❌ Login failed [#{response.status}]: #{response.body}"
        Result.failure("Login failed with status #{response.status}")
      end
    end

    def extract_auth_data(response, body)
      @token     = extract_token(response, body)
      @cookies   = extract_cookies(response)
      @user_info = body.dig("data", "user") || body["user"] || {}
      @profile_id = extract_profile_id(body)  # Add this
    end

    def extract_profile_id(body)
      body.dig("data", "user", "profileId") || 
      body.dig("data", "profileId") || 
      body["profileId"]
    end

    # Add getter
    def profile_id
      @profile_id
    end

    def extract_token(response, body)
      body["token"] ||
        body.dig("data", "token") ||
        extract_cookie_token(response)
    end

    def extract_cookie_token(response)
      raw = response.headers["set-cookie"] || ""
      match = raw.match(/nauk_at=([^;]+)/)
      match&.[](1)
    end

    def extract_cookies(response)
      raw_cookies = response.headers["set-cookie"] || ""
      raw_cookies.split(",").each_with_object({}) do |cookie, hash|
        key, value = cookie.split(";").first.to_s.split("=", 2)
        next if key.blank?

        hash[key.strip] = value&.strip
      end
    end
    def encrypt_password(plain_password)
      der        = Base64.decode64("MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBALrlQ+djR0RjJwBF1xuisHmdFv334MImK6LgzJhmLhN7B5yuEyaKoasgXQk3+OQglsOaBxEJ0j5PcTL3nbOvt80CAwEAAQ==")  # decode their public key
      public_key = OpenSSL::PKey::RSA.new(der)
      encrypted  = public_key.public_encrypt(plain_password, OpenSSL::PKey::RSA::PKCS1_PADDING)
      Base64.strict_encode64(encrypted)                 # send as base64
    end

    def login_payload
      {
        username: CONFIG[:email],
        password: CONFIG[:password],
        "isEncoded": false
      }
    end

    def validate_credentials!
      raise ArgumentError, "NAUKRI_EMAIL is not set" if CONFIG[:email].blank?
      raise ArgumentError, "NAUKRI_PASSWORD is not set" if CONFIG[:password].blank?
    end

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
