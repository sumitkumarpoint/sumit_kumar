# app/controllers/naukri_login_controller.rb
class NaukriLoginController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:login, :verify_otp]
  
  def index
    @session_status = Naukri::SessionManager.session_status
  end

  def login
    email = params[:email]
    password = params[:password]

    unless email.present? && password.present?
      return json_response(false, "Email and password required", {})
    end

    # Set credentials in memory for this request
    auth = Naukri::AuthService.new
    auth.instance_variable_set(:@temp_email, email)
    auth.instance_variable_set(:@temp_password, password)

    # Override CONFIG to use temp credentials
    allow_temp_credentials(auth, email, password)

    result = auth.perform_manual_login

    if result.success?
      # Save session
      Naukri::SessionManager.save_session(auth)
      json_response(true, "Login successful", { user: auth.user_info })
    elsif result.failure? && result.data[:requires_mfa]
      # MFA required
      session[:mfa_flow_id] = result.data[:flow_id]
      session[:mfa_email] = email
      
      json_response(
        false,
        "MFA required",
        {
          requires_mfa: true,
          flow_id: result.data[:flow_id],
          email: result.data[:email]
        }
      )
    else
      json_response(false, "Login failed: #{result.error}", {})
    end
  end

  def verify_otp
    otp_code = params[:otp_code]
    email = params[:email]
    password = params[:password]

    unless otp_code.present?
      return json_response(false, "OTP code required", {})
    end

    auth = Naukri::AuthService.new
    allow_temp_credentials(auth, email, password)
    auth.instance_variable_set(:@mfa_flow_id, session[:mfa_flow_id])

    result = auth.verify_otp(email, otp_code)

    if result.success?
      # Save session
      Naukri::SessionManager.save_session(auth)
      
      # Clear session
      session.delete(:mfa_flow_id)
      session.delete(:mfa_email)
      
      json_response(true, "OTP verified and logged in", { user: auth.user_info })
    else
      json_response(false, "OTP verification failed: #{result.error}", {})
    end
  end

  def logout
    Naukri::SessionManager.delete_session
    json_response(true, "Logged out successfully", {})
  end

  def status
    status_info = Naukri::SessionManager.session_status
    json_response(true, "Status retrieved", status_info)
  end

  def session_info
    session_data = Naukri::SessionManager.load_session
    
    if session_data
      json_response(true, "Session found", {
        email: session_data.dig("user_info", "username"),
        user_id: session_data.dig("user_info", "userId"),
        expires_at: session_data["expires_at"],
        created_at: session_data["created_at"]
      })
    else
      json_response(false, "No active session", {})
    end
  end

  private

  def allow_temp_credentials(auth, email, password)
    # Temporarily override credentials
    config = Rails.application.config_for(:naukri)
    allow_config = config.dup
    allow_config[:email] = email
    allow_config[:password] = password
    
    auth.instance_variable_set(:@config, allow_config)
  end

  def json_response(success, message, data)
    render json: {
      success: success,
      message: message,
      data: data
    }, status: success ? 200 : 422
  end
end
