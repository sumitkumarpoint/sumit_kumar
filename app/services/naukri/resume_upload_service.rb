# app/services/naukri/resume_upload_service.rb
require "faraday"
require "faraday/multipart"

module Naukri
  class ResumeUploadService
    CONFIG = Rails.application.config_for(:naukri).freeze

    FILE_UPLOAD_URL = "https://filevalidation.naukri.com/file".freeze

    def initialize(auth_service)
      @auth   = auth_service
      @logger = Rails.logger
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.timeout      = 30
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end
  
    # def finalize_resume(form_key, file_key)
    #   @logger.info "[Naukri::ResumeUploadService] Step 2: Finalizing resume..."
    #   # profile_id = @auth.profile_id
    #   profile_id = 'e25690abd4ff780186e479bc1d962da39cd0e1d2a543958d7e048c3bd0bbd3be'
    #   return Result.failure("Profile ID not available") if profile_id.blank?

    #   finalize_url = "https://www.naukri.com/cloudgateway-mynaukri/resman-aggregator-services/v0/users/self/profiles/#{profile_id}/advResume"

    #   response = connection.post(finalize_url) do |req|
    #     req.headers.merge!(@auth.auth_headers)
    #     req.headers["appid"]                    = "105"
    #     req.headers["systemid"]                 = "105"
    #     req.headers["x-http-method-override"]   = "PUT"
    #     req.headers["x-requested-with"]         = "XMLHttpRequest"
    #     req.headers["Content-Type"]             = "application/json"

    #     req.body = {textCV: {formKey: form_key, fileKey: file_key, textCvContent: nil}}.to_json
    #     # req.body = { resumePath: file_path }.to_json
    #   end

    #   @logger.info "[Finalize Response] Status: #{response.status}"

    #   if response.success?
    #     @logger.info "[Naukri::ResumeUploadService] ✅ Resume finalized!"
    #     Result.success(
    #       message:     "Resume uploaded successfully",
    #       # file_path:   file_path,
    #       uploaded_at: Time.current.iso8601
    #     )
    #   else
    #     @logger.error "[Naukri::ResumeUploadService] ❌ Finalize failed [#{response.status}]"
    #     Result.failure("Resume finalization failed: #{response.body}")
    #   end
    # rescue StandardError => e
    #   @logger.error "[Naukri::ResumeUploadService] Finalize error: #{e.message}"
    #   Result.failure("Finalize error: #{e.message}")
    # end

    def finalize_resume(form_key, file_key)
      @logger.info "[Naukri::ResumeUploadService] Step 2: Finalizing resume..."

      profile_id = 'e25690abd4ff780186e479bc1d962da39cd0e1d2a543958d7e048c3bd0bbd3be'
      return Result.failure("Profile ID not available") if profile_id.blank?

      finalize_url = "https://www.naukri.com/cloudgateway-mynaukri/resman-aggregator-services/v0/users/self/profiles/#{profile_id}/advResume"

      response = connection.post(finalize_url) do |req|
        # Merge auth headers
        req.headers.merge!(@auth.auth_headers)
        
        # Explicitly set required headers
        req.headers["appid"]                    = "105"
        req.headers["systemid"]                 = "105"
        req.headers["x-http-method-override"]   = "PUT"
        req.headers["x-requested-with"]         = "XMLHttpRequest"
        req.headers["Content-Type"]             = "application/json"
        
        # Ensure Authorization header is present
        req.headers["Authorization"] ||= "Bearer #{@auth.token}"
        
        # Explicitly set Cookie header with all cookies
        cookie_string = @auth.cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
        req.headers["Cookie"] = cookie_string
        
        @logger.info "[Finalize Headers] Auth: #{req.headers['Authorization']&.first(50)}..."
        @logger.info "[Finalize Headers] Cookies: #{cookie_string&.first(100)}..."

        req.body = {textCV: {formKey: form_key, fileKey: file_key, textCvContent: nil}}.to_json
      end

      # profile_id = 'e25690abd4ff780186e479bc1d962da39cd0e1d2a543958d7e048c3bd0bbd3be'

      # finalize_url = "https://www.naukri.com/cloudgateway-mynaukri/resman-aggregator-services/v0/users/self/profiles/#{profile_id}/advResume"

      # headers = @auth.auth_headers.merge(
      #   "appid" => "105",
      #   "systemid" => "105",
      #   "x-http-method-override" => "PUT",
      #   "x-requested-with" => "XMLHttpRequest",
      #   "Content-Type" => "application/json"
      # )

      # headers["Authorization"] ||= "Bearer #{@auth.token}"

      # cookie_string = @auth.cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
      # headers["Cookie"] = cookie_string

      # body = {
      #   textCV: {
      #     formKey: form_key,
      #     fileKey: file_key,
      #     textCvContent: nil
      #   }
      # }.to_json

      # curl = +"curl -X POST '#{finalize_url}'"

      # headers.each do |key, value|
      #   curl << " \\\n  -H '#{key}: #{value}'"
      # end

      # curl << " \\\n  --data-raw '#{body}'"

      # puts "\n========== CURL =========="
      # puts curl
      # puts "==========================\n"

      @logger.info "[Finalize Response] Status: #{response.status}"
      @logger.info "[Finalize Response] Body: #{response.body}"  # Log full response

      if response.success?
        @logger.info "[Naukri::ResumeUploadService] ✅ Resume finalized!"
        Result.success(
          message:     "Resume uploaded successfully",
          # file_path:   file_path,
          uploaded_at: Time.current.iso8601
        )
      else
        @logger.error "[Naukri::ResumeUploadService] ❌ Finalize failed [#{response.status}]"
        @logger.error "[Naukri::ResumeUploadService] Response: #{response.body}"
        Result.failure("Resume finalization failed [#{response.status}]: #{response.body}")
      end
    rescue StandardError => e
      @logger.error "[Naukri::ResumeUploadService] Error: #{e.message}"
      Result.failure("Finalize error: #{e.message}")
    end

      def delete_existing_resume
        @logger.info "[Naukri::ResumeUploadService] Deleting existing resume..."

        profile_id = 'e25690abd4ff780186e479bc1d962da39cd0e1d2a543958d7e048c3bd0bbd3be'
        return Result.failure("Profile ID not available") if profile_id.blank?

        delete_url = "https://www.naukri.com/cloudgateway-mynaukri/resman-aggregator-services/v0/users/self/profiles/#{profile_id}/deleteResume"

        response = connection.post(delete_url) do |req|
          req.headers.merge!(@auth.auth_headers)
          req.headers["appid"] = "105"
          req.headers["systemid"] = "105"
          req.headers["x-requested-with"] = "XMLHttpRequest"
          req.headers["x-http-method-override"] = "DELETE"
          req.headers["Content-Type"] = "application/json"
          req.body = ""
        end


        @logger.info "[Delete Response] Status: #{response.status}"

        if response.success? || response.status == 404  # 404 means no resume to delete
          @logger.info "[Naukri::ResumeUploadService] ✅ Delete successful"
          Result.success(message: "Resume deleted")
        else
          @logger.error "[Naukri::ResumeUploadService] ❌ Delete failed [#{response.status}]: #{response.body}"
          Result.failure("Delete failed: #{response.body}")
        end
      rescue StandardError => e
        @logger.error "[Naukri::ResumeUploadService] Error: #{e.message}"
        Result.failure("Delete error: #{e.message}")
      end


    def upload(resume_path = nil)
      resume_path = '/home/sumit/ruby/sumit_kumar/public/Sumit-Kumar-Senior-Rails-Developer-Resume.pdf'
      # resume_path ||= CONFIG[:resume_path]
      @logger.info "[Naukri::ResumeUploadService] Starting upload: #{resume_path}"

      return Result.failure("Not authenticated") unless @auth.logged_in?

      validator = FileValidator.new(resume_path)
      return Result.failure(validator.errors.join(", ")) unless validator.valid?
      # Delete existing resume first
      delete_result = delete_existing_resume
      if delete_result.failure?
        @logger.warn "[Naukri::ResumeUploadService] Delete failed: #{delete_result.error}"
        # Continue anyway - resume might not exist
      else
        @logger.info "[Naukri::ResumeUploadService] ✅ Existing resume deleted"
      end
      # Step 1: Upload file
      upload_result = upload_file(resume_path)
      return upload_result if upload_result.failure?

      file_path = upload_result.data[:file_path]
      form_key = upload_result.data[:form_key]
      file_key = upload_result.data[:file_key]
      @logger.info "[Naukri::ResumeUploadService] File uploaded: #{file_path}"

      # Step 2: Finalize in profile
      finalize_resume(form_key, file_key)
    end

    private
    def conn
      Faraday.new(url: FILE_UPLOAD_URL) do |f|
        f.request :multipart
        f.adapter Faraday.default_adapter
      end
    end


    def multipart_connection
      Faraday.new(url: FILE_UPLOAD_URL) do |f|
        f.request :multipart
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end
    end

    def upload_file(resume_path)
      @logger.info "[Naukri::ResumeUploadService] Step 1: Uploading file..."

      validator = FileValidator.new(resume_path)
      file_name = File.basename(resume_path)

      response = multipart_connection.post(FILE_UPLOAD_URL) do |req|
        req.headers.merge!(@auth.auth_headers)
        req.headers["appid"]            = "105"
        req.headers["systemid"]         = "105"
        req.headers["x-requested-with"] = "XMLHttpRequest"
        req.headers.delete("Content-Type")

        # Try "advResume" formKey instead of "resumeDocument"
        req.body = {
          formKey:  "F51f8e7e54e205",
          fileName: file_name,
          file: Faraday::FilePart.new(
            resume_path,
            validator.mime_type,
            file_name
          )
        }
      end

      @logger.info "[Upload Response] Status: #{response.status}"

      if response.success?
        body = parse_body(response.body)
        file_path = body.dig("data", "filePath") || body["filePath"]
        
        @logger.info "[Naukri::ResumeUploadService] ✅ File uploaded: #{file_path}"
        header = response.headers['location']

        form_key = header.match(/formKey=([A-Za-z0-9]+)/)[1]
        file_key = header.match(/fileKey=([A-Za-z0-9]+)/)[1]
        puts form_key
        puts file_key
        Result.success(file_path: file_path, form_key: form_key, file_key: file_key)
      else
        @logger.error "[Naukri::ResumeUploadService] ❌ Failed: #{response.body}"
        Result.failure("File upload failed: #{response.body}")
      end
    rescue StandardError => e
      @logger.error "[Error] #{e.message}"
      Result.failure("Upload error: #{e.message}")
    end

    def multipart_connection
      @multipart_connection ||= Faraday.new do |f|
        f.request :multipart
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