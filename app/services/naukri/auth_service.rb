# app/services/naukri/auth_service.rb
require "faraday"
require "json"

module Naukri
  class AuthService
    attr_reader :token, :cookies, :user_info, :profile_id, :refresh_token
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
      @token           = nil
      @refresh_token   = nil
      @cookies         = {}
      @user_info       = {}
      @profile_id      = nil
      @logger          = Rails.logger
      @mfa_flow_id     = nil
      @token_expires_at = nil
    end

    # Check if token is expired or expiring soon
    def token_expired?
      return true if @token.blank?
      return true if @token_expires_at.blank?
      
      @token_expires_at < Time.now
    end

    def token_expiring_soon?(within_minutes = 5)
      return true if @token.blank?
      return true if @token_expires_at.blank?
      
      @token_expires_at < (Time.now + within_minutes.minutes)
    end

    # Update stored auth in environment
    def save_to_env
      return false if @token.blank?
      
      cookie_string = @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
      
      @logger.info "[Naukri::AuthService] Saving credentials to environment..."
      
      # For local development - save to .env file
      if Rails.env.development?
        env_content = <<~ENV
          NAUKRI_AUTH_TOKEN=#{@token}
          NAUKRI_AUTH_COOKIES=#{cookie_string}
          NAUKRI_USE_STORED_AUTH=true
        ENV
        
        File.write(".env.naukri", env_content)
        @logger.info "[Naukri::AuthService] ✅ Saved to .env.naukri"
        true
      else
        @logger.warn "[Naukri::AuthService] In production - cannot auto-save. Manual update required."
        puts "\n" + "="*70
        puts "Save these to Render/production environment variables:"
        puts "="*70
        puts "NAUKRI_AUTH_TOKEN=#{@token}"
        puts "NAUKRI_AUTH_COOKIES=#{cookie_string}"
        puts "="*70
        true
      end
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
    def login(mfa_code = nil)
      # Use stored auth for Render
      if stored_cookie['naukri_use_store_auth'] == "true"
        @logger.info "[Naukri::AuthService] Using stored auth token"
        @token = stored_cookie['naukri_auth_token']

        cookie = stored_cookie['naukri_auth_cookies']
        @cookies = cookie_string.split("; ").each_with_object({}) do |cookie, hash|
          key, value = cookie.split("=", 2)
          hash[key.strip] = value if key.present? && value.present?
        end

        @profile_id = extract_profile_id_from_token(@token)
        extract_token_expiry(@token)
        if token_expired?
          perform_login
        # elsif token_expiring_soon?(within_minutes = 60)
        #   refresh_with_cookies_only
        end

        @logger.info "[Naukri::AuthService] ✅ Using stored credentials (expires at: #{@token_expires_at})"
        return Result.success(user_info: {}, token: @token)
      end

      @logger.info "[Naukri::AuthService] Attempting fresh login"
      validate_credentials!

      if mfa_code.present? && @mfa_flow_id.present?
        verify_mfa(mfa_code)
      else
        perform_login
      end
    end

    # def oldlogin(otp_code = nil)
    #   # Use stored auth if available
    #   if stored_cookie['naukri_use_store_auth'] =='true'
    #     @logger.info "[Naukri::AuthService] Using stored auth token"
    #     @token = stored_cookie['stored_cookie']
        
    #     if token_expired?(@token)
    #       @logger.warn "[Naukri::AuthService] ⚠️  Token expired"
    #       return Result.failure("Token expired. Run 'rails extract_auth' locally.")
    #     end
        
    #     cookie_string = stored_cookie['naukri_auth_cookies']
    #     @cookies = cookie_string.split("; ").each_with_object({}) do |cookie, hash|
    #       key, value = cookie.split("=", 2)
    #       hash[key.strip] = value if key.present? && value.present?
    #     end
        
    #     return Result.success(user_info: {}, token: @token)
    #   end

    #   @logger.info "[Naukri::AuthService] Attempting login"
    #   validate_credentials!

    #   # If OTP provided, verify it
    #   if otp_code.present? && @mfa_flow_id.present?
    #     return verify_otp(otp_code)
    #   end

    #   # Initial login attempt
    #   perform_login
    # end

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
        write_cookies(@token, cookie_string)
        Result.success(user_info: @user_info, token: @token)
      else
        @logger.error "[Naukri::AuthService] ❌ Login failed [#{response.status}]"
        Result.failure("Login failed: #{response.body}")
      end
    end

    # Verify OTP/MFA code
    def verify_otp(email, otp_code)
      @logger.info "[Naukri::AuthService] Verifying OTP..."

      response = connection.post(CONFIG[:login_otp_url]) do |req|
        req.headers.merge!(BASE_HEADERS)
        req.body = {
          username: email,
          # password: CONFIG[:password],
          # isEncoded: false,
          flowId: "mfa-login-email",
          isLoginByEmail: true,
          isLoginByMobile: false,
          token: otp_code
        }.to_json
      end

      body = parse_body(response.body)

      if response.success?
        extract_auth_data(response, body)
        write_cookies(@token, cookie_string)
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
      token = stored_cookie['naukri_auth_token']  || @token
      string = stored_cookie['naukri_auth_cookies'] || cookie_string
      # write_cookies(token, string)
      BASE_HEADERS.merge(
        "Authorization" => "Bearer #{token}",
        "Cookie"        => string
      ).compact
      # {"Content-Type"=>"application/json", "Accept"=>"application/json", "appid"=>"105", "clientid"=>"d3skt0p", "systemid"=>"jobseeker", "User-Agent"=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", "gid"=>"LOCATION,FIELD_DESIGNATION,INDUSTRY,SKILLS", "Authorization"=>"Bearer eyJraWQiOiIzIiwidHlwIjoiSldUIiwiYWxnIjoiUlM1MTIifQ.eyJkZXZpY2VUeXBlIjoiZDNza3QwcCIsInVkX3Jlc0lkIjoxMjUyNTUxMDksInN1YiI6IjEzMzk4NzEzNSIsInVkX3VzZXJuYW1lIjoic3VtaXRrdW1hcnBvaW50QGdtYWlsLmNvbSIsInVkX2lzRW1haWwiOnRydWUsImlzcyI6IkluZm9FZGdlIEluZGlhIFB2dC4gTHRkLiIsInVzZXJBZ2VudCI6Ik1vemlsbGEvNS4wIChNYWNpbnRvc2g7IEludGVsIE1hYyBPUyBYIDEwXzE1XzcpIEFwcGxlV2ViS2l0LzUzNy4zNiIsImlwQWRyZXNzIjoiMTUyLjU4LjE1My43MSIsInVkX2lzVGVjaE9wc0xvZ2luIjpmYWxzZSwidXNlcklkIjoxMzM5ODcxMzUsInN1YlVzZXJUeXBlIjoiam9ic2Vla2VyIiwidXNlclN0YXRlIjoiQVVUSEVOVElDQVRFRCIsInVkX2lzUGFpZENsaWVudCI6ZmFsc2UsInVkX2VtYWlsVmVyaWZpZWQiOnRydWUsInVzZXJUeXBlIjoiam9ic2Vla2VyIiwic2Vzc2lvblN0YXRUaW1lIjoiMjAyNi0wNi0wM1QxNzozMjo0NiIsInVkX2VtYWlsIjoic3VtaXRrdW1hcnBvaW50QGdtYWlsLmNvbSIsInVzZXJSb2xlIjoidXNlciIsImV4cCI6MTc4MDQ5MTc2NiwidG9rZW5UeXBlIjoiYWNjZXNzVG9rZW4iLCJpYXQiOjE3ODA0ODgxNjYsImp0aSI6ImQwZWI2OTJhZDRlYjQ4YWNhYmMyMzcxZWU3NGM1ZDBiIiwicG9kSWQiOiJwcm9kLTc1YzdkOTk5ZC1rd2o0aiJ9.McUpSuaMIWD-pJNfRD5pIxplJx49DmGEls4RWqJ3B7mXfPA4hMPwS5UcsSOhQt2l4syJuHvYQOE45oSXoXuoXgmATsDNkztf6eVmJQLTydSEEIvqSbpgjnelNbopVToUADGd-piBUsJn4ZImJYv0y6omhfakQTpl4kTgqB8ez8GE8Xpv6y2wFCWYkISUB9b1kpXXyVjRrgMGPFl0dITJdXJcXFx57jpirFDYBiMN7Z_POdrjTDrb_2JpMeVk3AI9xJ4FJrCcX4I4xLWDHpmUtdL56qLfUpL1oeEG8gYQNWio4fG2RWTti3S4WaB2_eVQU_4yw_M5n54FPQZGd0m9vQ", "Cookie"=>"nauk_at=eyJraWQiOiIzIiwidHlwIjoiSldUIiwiYWxnIjoiUlM1MTIifQ.eyJkZXZpY2VUeXBlIjoiZDNza3QwcCIsInVkX3Jlc0lkIjoxMjUyNTUxMDksInN1YiI6IjEzMzk4NzEzNSIsInVkX3VzZXJuYW1lIjoic3VtaXRrdW1hcnBvaW50QGdtYWlsLmNvbSIsInVkX2lzRW1haWwiOnRydWUsImlzcyI6IkluZm9FZGdlIEluZGlhIFB2dC4gTHRkLiIsInVzZXJBZ2VudCI6Ik1vemlsbGEvNS4wIChNYWNpbnRvc2g7IEludGVsIE1hYyBPUyBYIDEwXzE1XzcpIEFwcGxlV2ViS2l0LzUzNy4zNiIsImlwQWRyZXNzIjoiMTUyLjU4LjE1My43MSIsInVkX2lzVGVjaE9wc0xvZ2luIjpmYWxzZSwidXNlcklkIjoxMzM5ODcxMzUsInN1YlVzZXJUeXBlIjoiam9ic2Vla2VyIiwidXNlclN0YXRlIjoiQVVUSEVOVElDQVRFRCIsInVkX2lzUGFpZENsaWVudCI6ZmFsc2UsInVkX2VtYWlsVmVyaWZpZWQiOnRydWUsInVzZXJUeXBlIjoiam9ic2Vla2VyIiwic2Vzc2lvblN0YXRUaW1lIjoiMjAyNi0wNi0wM1QxNzozMjo0NiIsInVkX2VtYWlsIjoic3VtaXRrdW1hcnBvaW50QGdtYWlsLmNvbSIsInVzZXJSb2xlIjoidXNlciIsImV4cCI6MTc4MDQ5MTc2NiwidG9rZW5UeXBlIjoiYWNjZXNzVG9rZW4iLCJpYXQiOjE3ODA0ODgxNjYsImp0aSI6ImQwZWI2OTJhZDRlYjQ4YWNhYmMyMzcxZWU3NGM1ZDBiIiwicG9kSWQiOiJwcm9kLTc1YzdkOTk5ZC1rd2o0aiJ9.McUpSuaMIWD-pJNfRD5pIxplJx49DmGEls4RWqJ3B7mXfPA4hMPwS5UcsSOhQt2l4syJuHvYQOE45oSXoXuoXgmATsDNkztf6eVmJQLTydSEEIvqSbpgjnelNbopVToUADGd-piBUsJn4ZImJYv0y6omhfakQTpl4kTgqB8ez8GE8Xpv6y2wFCWYkISUB9b1kpXXyVjRrgMGPFl0dITJdXJcXFx57jpirFDYBiMN7Z_POdrjTDrb_2JpMeVk3AI9xJ4FJrCcX4I4xLWDHpmUtdL56qLfUpL1oeEG8gYQNWio4fG2RWTti3S4WaB2_eVQU_4yw_M5n54FPQZGd0m9vQ; nauk_rt=d0eb692ad4eb48acabc2371ee74c5d0b; is_login=1; nauk_sid=d0eb692ad4eb48acabc2371ee74c5d0b; nauk_otl=d0eb692ad4eb48acabc2371ee74c5d0b; failLoginCount=0; NKWAP=0a11a4ef2a2d292d958805de199711c43ae1b345417f33a0f9f2fdf03dc560d19a86cc384cde9c370d99ad6a3af22255~0a11a4ef2a2d292d958805de199711c43ae1b345417f33a0f9f2fdf03dc560d19a86cc384cde9c370d99ad6a3af22255~1~0; MYNAUKRI[UNID]=e2662cc67fd148449a5344a938432eda; nauk_ps=default; nauk_cs=default"}
      end

    # Validate if stored cookies are still valid
    def validate_stored_cookies
      @logger.info "[Naukri::AuthService] Validating stored cookies..."
      
      if stored_cookie['naukri_use_store_auth'] == 'true'
        return Result.failure("Stored auth not enabled")
      end

      @token = stored_cookie['naukri_auth_token']
      
      cookie_string = stored_cookie['naukri_auth_cookies']
      @cookies = cookie_string.split("; ").each_with_object({}) do |cookie, hash|
        key, value = cookie.split("=", 2)
        hash[key.strip] = value if key.present? && value.present?
      end

      # Try to call a protected endpoint to validate cookies
      response = connection.get("https://www.naukri.com/central-login-services/v0/credentials/login-status") do |req|
        req.headers.merge!(BASE_HEADERS)
        req.headers["Authorization"] = "Bearer #{@token}"
        
        cookie_string = @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
        req.headers["Cookie"] = cookie_string
      end

      if response.success?
        body = parse_body(response.body)
        extract_auth_data(response, body)
        
        @logger.info "[Naukri::AuthService] ✅ Cookies are still valid"
        Result.success(user_info: @user_info, token: @token)
      else
        @logger.warn "[Naukri::AuthService] ⚠️  Cookies expired [#{response.status}]"
        Result.failure("Cookies no longer valid - need to re-login", { requires_login: true })
      end
    rescue StandardError => e
      @logger.error "[Naukri::AuthService] Validation error: #{e.message}"
      Result.failure("Cookie validation error: #{e.message}")
    end

    def fetch_profile
      url = "https://www.naukri.com/cloudgateway-mynaukri/resman-aggregator-services/v2/users/self"

      response = connection.get(url) do |req|
        req.params["expand_level"] = 4

        req.headers.merge!(self.auth_headers)

        req.headers["Accept"]           = "application/json"
        req.headers["Content-Type"]     = "application/json"
        req.headers["appid"]            = "105"
        req.headers["clientid"]         = "d3skt0p"
        req.headers["systemid"]         = "Naukri"
        req.headers["X-Requested-With"] = "XMLHttpRequest"
        req.headers["Referer"]          = "https://www.naukri.com/mnjuser/profile"
      end

      Rails.logger.info "Status: #{response.status}"

      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error("Naukri API Error: #{response.status} - #{response.body}")
        nil
      end
    end

    # Refresh cookies by making a request - Naukri might return new ones
    def refresh_with_cookies_only
      @logger.info "[Naukri::AuthService] Attempting to refresh using cookies..."

      # @token = stored_cookie['naukri_auth_token']
      
      cookie_string = stored_cookie['naukri_auth_cookies']
      @cookies = cookie_string.split("; ").each_with_object({}) do |cookie, hash|
        key, value = cookie.split("=", 2)
        hash[key.strip] = value if key.present? && value.present?
      end

      url = "https://www.naukri.com/cloudgateway-mynaukri/resman-aggregator-services/v2/users/self"

      response = connection.get(url) do |req|
        req.params["expand_level"] = 4

        req.headers.merge!(self.auth_headers)

        req.headers["Accept"]           = "application/json"
        req.headers["Content-Type"]     = "application/json"
        req.headers["appid"]            = "105"
        req.headers["clientid"]         = "d3skt0p"
        req.headers["systemid"]         = "Naukri"
        req.headers["X-Requested-With"] = "XMLHttpRequest"
        req.headers["Referer"]          = "https://www.naukri.com/mnjuser/profile"
      end

      if response.success?
        body = parse_body(response.body)
        
        # Extract refreshed cookies from response headers if any
        new_cookies = extract_cookies_from_headers(response)
        Naukri::SessionManager.update_cookies(new_cookies)
        cookies_updated = true
        @cookies.merge!(new_cookies) if new_cookies.any?
        token = @token || stored_cookie['naukri_auth_token']
        extract_auth_data(response, body)
        write_cookies(token, cookie_string)
        @logger.info "[Naukri::AuthService] ✅ Cookies refreshed via API call"
        Result.success(user_info: @user_info, token: @token)
      else
        @logger.warn "[Naukri::AuthService] ⚠️  Cookie refresh failed [#{response.status}]"
        Result.failure("Could not refresh cookies - cookies may be expired", { requires_login: true })
      end
    rescue StandardError => e
      @logger.error "[Naukri::AuthService] Refresh error: #{e.message}"
      Result.failure("Cookie refresh error: #{e.message}")
    end

    def stored_cookie
      public_path = Rails.root.join('tmp')
      JSON.parse(File.read(public_path + 'cookie.json')) rescue JSON.parse(File.read(Rails.root.join('public') + 'cookie.json'))
    end

    def write_cookies(token, cookie)
      data_file = public_path = Rails.root.join('tmp', 'cookie.json')
      new_data = {
        naukri_use_store_auth: "true",
        naukri_auth_token: token,
        naukri_auth_cookies: cookie
      }

      File.write(data_file, JSON.pretty_generate(new_data))
    end

    # Make perform_login accessible
    def perform_manual_login
      response = connection.post(CONFIG[:login_url]) do |req|
        req.headers.merge!(BASE_HEADERS)
        req.body = login_payload.to_json
      end
      handle_login_response(response)
    rescue Faraday::Error => e
      @logger.error "[Naukri::AuthService] Connection error: #{e.message}"
      Result.failure("Connection failed: #{e.message}")
    end

    private

    def extract_token_expiry(token)
      begin
        payload = JWT.decode(token, nil, false)[0]
        @token_expires_at = Time.at(payload["exp"])
        @logger.info "[Auth] Token expires at: #{@token_expires_at} (in #{((payload["exp"] - Time.now.to_i) / 3600).round(1)} hours)"
      rescue => e
        @logger.warn "[Auth] Could not extract token expiry: #{e.message}"
        @token_expires_at = Time.now + 24.hours  # Assume 24 hours
      end
    end

    def extract_profile_id_from_token(token)
      begin
        payload = JWT.decode(token, nil, false)[0]
        profile_id = payload["poId"] || payload["profileId"] || "self"
        @logger.info "[Auth] Profile ID: #{profile_id}"
        profile_id
      rescue => e
        @logger.warn "[Auth] Could not extract profile_id: #{e.message}"
        "self"
      end
    end

    def extract_cookies_from_headers(response)
      raw_cookies = response.headers["set-cookie"].to_s
      raw_cookies.split(",").each_with_object({}) do |cookie, hash|
        key, value = cookie.split(";").first.to_s.split("=", 2)
        next if key.blank?
        hash[key.strip] = value&.strip
      end
    end

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
