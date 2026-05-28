# app/services/naukri/uploader.rb
# Main facade — use this in jobs, controllers, and rake tasks
module Naukri
  class Uploader
    attr_reader :auth, :result

    def initialize
      @auth   = AuthService.new
      @logger = Rails.logger
    end

    # Full flow: login → upload → return result
    def run(resume_path = nil)
      login_result = @auth.login
      return login_result if login_result.failure?

      uploader = ResumeUploadService.new(@auth)
      @result  = uploader.upload(resume_path)

      log_result
      @result
    end

    # Full flow including profile refresh
    def run_with_refresh(resume_path = nil)
      login_result = @auth.login
      return login_result if login_result.failure?

      upload_result = ResumeUploadService.new(@auth).upload(resume_path)
      return upload_result if upload_result.failure?

      profile_result = ProfileService.new(@auth).refresh_profile

      @result = Result.success(
        upload:  upload_result.data,
        profile: profile_result.data
      )

      log_result
      @result
    end

    private

    def log_result
      if @result.success?
        @logger.info "[Naukri::Uploader] ✅ All done! #{@result.data}"
      else
        @logger.error "[Naukri::Uploader] ❌ Failed: #{@result.error}"
      end
    end
  end
end
