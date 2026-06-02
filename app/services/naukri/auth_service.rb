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
    # def login
    #   @logger.info "[Naukri::AuthService] Attempting login for #{CONFIG[:email]}"

    #   validate_credentials!

    #   response = connection.post(CONFIG[:login_url]) do |req|
    #     req.headers.merge!(BASE_HEADERS)
    #     req.body = login_payload.to_json
    #   end

    #   handle_response(response)
    # rescue Faraday::ConnectionFailed => e
    #   @logger.error "[Naukri::AuthService] Connection failed: #{e.message}"
    #   Result.failure("Connection failed: #{e.message}")
    # rescue Faraday::TimeoutError
    #   @logger.error "[Naukri::AuthService] Request timed out"
    #   Result.failure("Request timed out")
    # end
    # def login(mfa_code = nil)
    #   # Use stored auth for Render/external environments
    #   if ENV["NAUKRI_USE_STORED_AUTH"] == "true" || Rails.application.credentials.naukri_use_store_auth.to_s =="true"
    #     @logger.info "[Naukri::AuthService] Using stored auth token from Render"
    #     @token = ENV["NAUKRI_AUTH_TOKEN"] || Rails.application.credentials.naukri_auth_token

    #     # Parse cookies from stored string
    #     cookie_string = ENV["NAUKRI_AUTH_COOKIES"].to_s || Rails.application.credentials.naukri_auth_cookies
    #     @cookies = cookie_string.split("; ").each_with_object({}) do |cookie, hash|
    #       key, value = cookie.split("=", 2)
    #       hash[key.strip] = value if key.present? && value.present?
    #     end

    #     @logger.info "[Naukri::AuthService] ✅ Using stored credentials"
    #     return Result.success(user_info: {}, token: @token)
    #   end

    #   @logger.info "[Naukri::AuthService] Attempting login for #{CONFIG[:email]}"
    #   validate_credentials!

    #   if mfa_code.present? && @mfa_flow_id.present?
    #     verify_mfa(mfa_code)
    #   else
    #     perform_login
    #   end
    # end

    def login(otp_code = nil)
      # Use stored auth if available
      if Rails.application.credentials.naukri_use_store_auth.to_s =="true"
        @logger.info "[Naukri::AuthService] Using stored auth token"
        @token = Rails.application.credentials.naukri_auth_token
        
        # if token_expired?(@token)
        #   @logger.warn "[Naukri::AuthService] ⚠️  Token expired"
        #   return Result.failure("Token expired. Run 'rails extract_auth' locally.")
        # end
        
        cookie_string = Rails.application.credentials.naukri_auth_cookies
        @cookies = cookie_string.split("; ").each_with_object({}) do |cookie, hash|
          key, value = cookie.split("=", 2)
          hash[key.strip] = value if key.present? && value.present?
        end
        
        return Result.success(user_info: {}, token: @token)
      end

      @logger.info "[Naukri::AuthService] Attempting login"
      validate_credentials!

      # If OTP provided, verify it
      if otp_code.present? && @mfa_flow_id.present?
        return verify_otp(otp_code)
      end

      # Initial login attempt
      perform_login
    end

    def perform_login
      response = connection.post(CONFIG[:login_url]) do |req|
        req.headers.merge!(BASE_HEADERS)
        req.body = login_payload.to_json
      end

      handle_login_response(response)
    rescue Faraday::Error => e
      @logger.error "[Naukri::AuthService] Connection error: #{e.message}"
      Result.failure("Connection failed: #{e.message}")
    end

    def handle_login_response(response)
      body = parse_body(response.body)

      # Check if MFA is required
      if response.status == 403 && body["message"]&.include?("MFA")
        @logger.warn "[Naukri::AuthService] ⚠️  MFA required"
        @mfa_flow_id = body.dig("data", "flowId")
        email = body.dig("data", "email")
        
        return Result.failure(
          "MFA Required: OTP sent to #{email}. Use: rails naukri:login OTP=123456",
          { requires_mfa: true, flow_id: @mfa_flow_id, email: email }
        )
      end

      if response.success?
        extract_auth_data(response, body)
        @logger.info "[Naukri::AuthService] ✅ Login successful"
        Result.success(user_info: @user_info, token: @token)
      else
        @logger.error "[Naukri::AuthService] ❌ Login failed [#{response.status}]"
        Result.failure("Login failed: #{response.body}")
      end
    end

    # Verify OTP/MFA code
    def verify_otp(otp_code)
      @logger.info "[Naukri::AuthService] Verifying OTP..."

      response = connection.post(CONFIG[:login_url]) do |req|
        req.headers.merge!(BASE_HEADERS)
        req.body = {
          username: CONFIG[:email],
          password: CONFIG[:password],
          isEncoded: false,
          flowId: @mfa_flow_id,
          otp: otp_code
        }.to_json
      end

      body = parse_body(response.body)

      if response.success?
        extract_auth_data(response, body)
        @logger.info "[Naukri::AuthService] ✅ OTP verified, login successful"
        Result.success(user_info: @user_info, token: @token)
      else
        @logger.error "[Naukri::AuthService] ❌ OTP verification failed [#{response.status}]"
        Result.failure("OTP verification failed: #{response.body}")
      end
    rescue Faraday::Error => e
      @logger.error "[Naukri::AuthService] OTP error: #{e.message}"
      Result.failure("OTP error: #{e.message}")
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
        byebug
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
      @cookies   = extract_cookies_from_response(body)  # Use new method
      @user_info = body.dig("userInfo") || body.dig("data", "user") || {}
      @profile_id = @user_info.dig("userData", "resId") || @user_info["profileId"]
    end

    def extract_cookies_from_response(body)
      # Handle array-based cookie response from login API
      cookies_array = body["cookies"] || []
      
      cookies_array.each_with_object({}) do |cookie, hash|
        hash[cookie["name"]] = cookie["value"]
      end
    end

    def extract_cookies(response)
      # Fallback for header-based cookies
      raw_cookies = response.headers["set-cookie"].to_s
      raw_cookies.split(",").each_with_object({}) do |cookie, hash|
        key, value = cookie.split(";").first.to_s.split("=", 2)
        next if key.blank?
        hash[key.strip] = value&.strip
      end
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
        username: Rails.application.credentials.naukri_email,
        password: Rails.application.credentials.naukri_password,
        "isEncoded": false
      }
    end

    def validate_credentials!
      raise ArgumentError, "NAUKRI_EMAIL is not set" if Rails.application.credentials.naukri_email.blank?
      raise ArgumentError, "NAUKRI_PASSWORD is not set" if Rails.application.credentials.naukri_password.blank?
    end
    
    # def handle_login_response(response)
    #   body = parse_body(response.body)

    #   # Check if MFA is required
    #   if response.status == 403 && body["message"]&.include?("MFA")
    #     @logger.warn "[Naukri::AuthService] ⚠️  MFA required"
    #     @mfa_flow_id = body.dig("data", "flowId")
    #     email = body.dig("data", "email")
        
    #     return Result.failure(
    #       "MFA Required: Verification code sent to #{email}. Run: rails naukri:verify_mfa CODE=123456",
    #       { requires_mfa: true, flow_id: @mfa_flow_id, email: email }
    #     )
    #   end

    #   if response.success?
    #     extract_auth_data(response, body)
    #     @logger.info "[Naukri::AuthService] ✅ Login successful"
    #     Result.success(user_info: @user_info, token: @token)
    #   else
    #     @logger.error "[Naukri::AuthService] ❌ Login failed [#{response.status}]: #{response.body}"
    #     Result.failure("Login failed: #{response.body}")
    #   end
    # end

    def verify_mfa(mfa_code)
      @logger.info "[Naukri::AuthService] Verifying MFA code..."

      mfa_url = "#{CONFIG[:login_url]}/mfa/verify"

      response = connection.post(mfa_url) do |req|
        req.headers.merge!(BASE_HEADERS)
        req.body = {
          flowId: @mfa_flow_id,
          otp:    mfa_code
        }.to_json
      end

      if response.success?
        body = parse_body(response.body)
        extract_auth_data(response, body)
        @logger.info "[Naukri::AuthService] ✅ MFA verified"
        Result.success(user_info: @user_info, token: @token)
      else
        @logger.error "[Naukri::AuthService] ❌ MFA verification failed"
        Result.failure("MFA verification failed: #{response.body}")
      end
    end

    # def perform_login
    #   response = connection.post(CONFIG[:login_url]) do |req|
    #     req.headers.merge!(BASE_HEADERS)
    #     req.body = login_payload.to_json
    #   end

    #   handle_login_response(response)
    # rescue Faraday::Error => e
    #   @logger.error "[Naukri::AuthService] Connection error: #{e.message}"
    #   Result.failure("Connection failed: #{e.message}")
    # end

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



# # app/services/naukri/auth_service.rb
# require "faraday"
# require "json"

# module Naukri
#   class AuthService
#     attr_reader :token, :cookies, :user_info, :profile_id

#     CONFIG = Rails.application.config_for(:naukri).freeze

#     BASE_HEADERS = {
#       "Content-Type"    => "application/json",
#       "Accept"          => "application/json",
#       "appid"           => "105",
#       "clientid"        => "d3skt0p",
#       "systemid"        => "jobseeker",
#       "User-Agent"      => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
#       "gid"             => "LOCATION,FIELD_DESIGNATION,INDUSTRY,SKILLS"
#     }.freeze

#     def initialize
#       @token     = nil
#       @cookies   = {}
#       @user_info = {}
#       @profile_id = nil
#       @logger    = Rails.logger
#       @mfa_flow_id = nil
#     end

#     def login(mfa_code = nil)
#       @logger.info "[Naukri::AuthService] Attempting login for #{CONFIG[:email]}"
#       validate_credentials!

#       if mfa_code.present? && @mfa_flow_id.present?
#         verify_mfa(mfa_code)
#       else
#         perform_login
#       end
#     end

#     def logged_in?
#       @token.present? || @cookies.any?
#     end

#     def cookie_string
#       @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
#     end

#     def auth_headers
#       BASE_HEADERS.merge(
#         "Authorization" => "Bearer #{@token}",
#         "Cookie"        => cookie_string
#       ).compact
#     end

#     private

#     def perform_login
#       response = connection.post(CONFIG[:login_url]) do |req|
#         req.headers.merge!(BASE_HEADERS)
#         req.body = login_payload.to_json
#       end

#       handle_login_response(response)
#     rescue Faraday::Error => e
#       @logger.error "[Naukri::AuthService] Connection error: #{e.message}"
#       Result.failure("Connection failed: #{e.message}")
#     end

#     def handle_login_response(response)
#       body = parse_body(response.body)

#       # Check if MFA is required
#       if response.status == 403 && body["message"]&.include?("MFA")
#         @logger.warn "[Naukri::AuthService] ⚠️  MFA required"
#         @mfa_flow_id = body.dig("data", "flowId")
#         email = body.dig("data", "email")
        
#         return Result.failure(
#           "MFA Required: Verification code sent to #{email}. Run: rails naukri:verify_mfa CODE=123456",
#           { requires_mfa: true, flow_id: @mfa_flow_id, email: email }
#         )
#       end

#       if response.success?
#         extract_auth_data(response, body)
#         @logger.info "[Naukri::AuthService] ✅ Login successful"
#         Result.success(user_info: @user_info, token: @token)
#       else
#         @logger.error "[Naukri::AuthService] ❌ Login failed [#{response.status}]: #{response.body}"
#         Result.failure("Login failed: #{response.body}")
#       end
#     end

#     def verify_mfa(mfa_code)
#       @logger.info "[Naukri::AuthService] Verifying MFA code..."

#       mfa_url = "#{CONFIG[:login_url]}/mfa/verify"

#       response = connection.post(mfa_url) do |req|
#         req.headers.merge!(BASE_HEADERS)
#         req.body = {
#           flowId: @mfa_flow_id,
#           otp:    mfa_code
#         }.to_json
#       end

#       if response.success?
#         body = parse_body(response.body)
#         extract_auth_data(response, body)
#         @logger.info "[Naukri::AuthService] ✅ MFA verified"
#         Result.success(user_info: @user_info, token: @token)
#       else
#         @logger.error "[Naukri::AuthService] ❌ MFA verification failed"
#         Result.failure("MFA verification failed: #{response.body}")
#       end
#     end

#     def extract_auth_data(response, body)
#       @token     = extract_token(response, body)
#       @cookies   = extract_cookies(response)
#       @user_info = body.dig("data", "user") || body["user"] || {}
#       @profile_id = @user_info.dig("profileId") || @user_info["profileId"]
#     end

#     def extract_token(response, body)
#       body["token"] ||
#         body.dig("data", "token") ||
#         extract_cookie_token(response)
#     end

#     def extract_cookie_token(response)
#       raw = response.headers["set-cookie"].to_s
#       match = raw.match(/nauk_at=([^;]+)/)
#       match&.[](1)
#     end

#     def extract_cookies(response)
#       raw_cookies = response.headers["set-cookie"].to_s
#       raw_cookies.split(",").each_with_object({}) do |cookie, hash|
#         key, value = cookie.split(";").first.to_s.split("=", 2)
#         next if key.blank?
#         hash[key.strip] = value&.strip
#       end
#     end

#     def login_payload
#       {
#         username:  CONFIG[:email],
#         password:  CONFIG[:password],
#         isEncoded: false
#       }
#     end

#     def validate_credentials!
#       raise ArgumentError, "NAUKRI_EMAIL not set" if CONFIG[:email].blank?
#       raise ArgumentError, "NAUKRI_PASSWORD not set" if CONFIG[:password].blank?
#     end

#     def connection
#       @connection ||= Faraday.new do |f|
#         f.options.timeout      = 30
#         f.options.open_timeout = 10
#         f.adapter Faraday.default_adapter
#       end
#     end

#     def parse_body(body)
#       JSON.parse(body)
#     rescue JSON::ParserError
#       {}
#     end
#   end
# end