# lib/tasks/naukri.rake
namespace :naukri do
  desc "Upload resume to Naukri.com (RESUME_PATH=... optional)"
  task upload_resume: :environment do
    public_path = Rails.root.join('public', 'resumes')
    data = JSON.parse(File.read(Rails.root.join('tmp') + 'data.json')) rescue {}
    resume_path = (public_path + data['filename']).to_s if data.length.positive?
    resume_path ||= Rails.root.join("public/Sumit-Kumar-Senior-Rails-Developer-Resume.pdf")
    puts "=" * 60
    puts "📄 Naukri Resume Uploader"
    puts "=" * 60
    puts "  Resume : #{resume_path || 'Using config default'}"
    puts "  Time   : #{Time.current}"
    puts "=" * 60

    result = Naukri::Uploader.new.run(resume_path)

    if result.success?
      puts "\n✅ SUCCESS: Resume uploaded to Naukri.com!"
      puts "   Uploaded at: #{result.data[:uploaded_at]}"
    else
      puts "\n❌ FAILED: #{result.error}"
      exit 1
    end
  end

  desc "Login with OTP verification  |  OTP=123456"
  task login: :environment do
    otp = ENV["OTP"]
    
    puts "="*60
    puts "🔐 Naukri Login with OTP Verification"
    puts "="*60
    
    unless otp.present?
      puts "\n⚠️  First attempt (will request OTP via email):\n"
      puts "Step 1: Run this to get OTP\n"
      puts "  rails naukri:login\n"
      puts "\nStep 2: Check your email for OTP\n"
      puts "Step 3: Run with OTP\n"
      puts "  rails naukri:login OTP=123456\n\n"
      
      auth = Naukri::AuthService.new
      result = auth.login
      
      if result.failure? && result.data[:requires_mfa]
        puts "✅ OTP sent to: #{result.data[:email]}"
        puts "\n📧 Check your email and run:\n"
        puts "   rails naukri:login OTP=123456\n"
      else
        puts "❌ Error: #{result.error}"
        exit 1
      end
    else
      # OTP provided - verify it
      puts "\n🔓 Verifying OTP: #{otp}\n"
      
      auth = Naukri::AuthService.new
      auth.instance_variable_set(:@mfa_flow_id, "mfa-login-email")  # Set from first attempt
      result = auth.login(otp)
      
      if result.success?
        token = auth.token
        cookies = auth.cookies
        
        cookie_string = cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
        
        puts "✅ Login successful!\n\n"
        puts "="*70
        puts "Add to Render environment variables:"
        puts "="*70
        puts "\nNAUKRI_AUTH_TOKEN=#{token}\n\n"
        puts "NAUKRI_AUTH_COOKIES=#{cookie_string}\n\n"
        puts "NAUKRI_USE_STORED_AUTH=true\n"
        puts "="*70
      else
        puts "❌ OTP verification failed: #{result.error}"
        exit 1
      end
    end
  end

  desc "Delete existing resume"
  task delete_resume: :environment do
    puts "="*60
    puts "🗑️  Naukri Resume Delete"
    puts "="*60

    auth         = Naukri::AuthService.new
    login_result = auth.login

    unless login_result.success?
      puts "❌ Login failed: #{login_result.error}"
      exit 1
    end

    uploader = Naukri::Uploader.new
    uploader.instance_variable_set(:@auth, auth)
    
    service = Naukri::ResumeUploadService.new(auth)
    result = service.send(:delete_existing_resume)

    if result.success?
      puts "✅ Resume deleted successfully!"
    else
      puts "❌ Delete failed: #{result.error}"
      exit 1
    end
  end

  desc "Delete then upload resume"
  task delete_and_upload_resume: :environment do
    resume_path = Rails.root.join("public/Sumit-Kumar-Senior-Rails-Developer-Resume.pdf")

    puts "="*60
    puts "🔄 Naukri Resume Delete & Upload"
    puts "="*60
    puts "  Resume : #{resume_path || 'Using config default'}"
    puts "  Time   : #{Time.current}"
    puts "="*60

    result = Naukri::Uploader.new.run(resume_path)

    if result.success?
      puts "\n✅ SUCCESS: Resume deleted and uploaded!"
      puts "   Uploaded at: #{result.data[:uploaded_at]}"
    else
      puts "\n❌ FAILED: #{result.error}"
      exit 1
    end
  end


  desc "Extract auth token and cookies for Render"
  task extract_auth: :environment do
    puts "🔑 Extracting auth credentials..."
    
    auth = Naukri::AuthService.new
    result = auth.login
    
    if result.success?
      token = auth.token
      cookies = auth.cookies
      
      # Format cookies string
      cookie_string = cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
      
      puts "\n✅ Authentication successful!"
      puts "\n" + "="*60
      puts "Add to Render environment variables:"
      puts "="*60
      puts "\nNAUKRI_AUTH_TOKEN=#{token}\n\n"
      puts "NAUKRI_AUTH_COOKIES=#{cookie_string}\n\n"
      puts "NAUKRI_USE_STORED_AUTH=true\n"
      puts "="*60
      
      # Also save to .env.render for reference
      File.write(".env.render", <<~ENV)
        NAUKRI_AUTH_TOKEN=#{token}
        NAUKRI_AUTH_COOKIES=#{cookie_string}
        NAUKRI_USE_STORED_AUTH=true
      ENV
      
      puts "\n✅ Saved to .env.render for reference"
    else
      puts "❌ Login failed: #{result.error}"
      exit 1
    end
  end

  desc "Upload resume AND refresh profile visibility"
  task upload_and_refresh: :environment do

    public_path = Rails.root.join('tmp', 'resumes')
    data = JSON.parse(File.read(Rails.root.join('tmp') + 'data.json')) rescue {}
    resume_path = (public_path + data['filename']).to_s if data.length.positive?
    resume_path ||= Rails.root.join("public/Sumit-Kumar-Senior-Rails-Developer-Resume.pdf")
    puts "🚀 Running full upload + profile refresh..."

    result = Naukri::Uploader.new.run_with_refresh(resume_path)

    if result.success?
      puts "✅ Done! Resume uploaded and profile refreshed."
    else
      puts "❌ Failed: #{result.error}"
      exit 1
    end
  end

  desc "Refresh Naukri profile activity (no upload)"
  task refresh_profile: :environment do
    puts "🔄 Refreshing Naukri profile..."

    auth = Naukri::AuthService.new
    login_result = auth.login

    unless login_result.success?
      puts "❌ Login failed: #{login_result.error}"
      exit 1
    end

    result = Naukri::ProfileService.new(auth).refresh_profile

    if result.success?
      puts "✅ Profile refreshed at #{result.data[:refreshed_at]}"
    else
      puts "❌ Failed: #{result.error}"
      exit 1
    end
  end

  desc "Queue resume upload as a background job (requires Sidekiq)"
  task enqueue_upload: :environment do
    public_path = Rails.root.join('tmp', 'resumes')
    data = JSON.parse(File.read(Rails.root.join('tmp') + 'data.json')) rescue {}
    resume_path = (public_path + data['filename']).to_s if data.length.positive?
    resume_path ||= Rails.root.join("public/Sumit-Kumar-Senior-Rails-Developer-Resume.pdf")
    puts "⏰ Enqueueing NaukriResumeUploadJob..."
    NaukriResumeUploadJob.perform_later(resume_path)
    puts "✅ Job queued! Check Sidekiq dashboard."
  end

  desc "Validate resume file before uploading"
  task validate_resume: :environment do
    public_path = Rails.root.join('tmp', 'resumes')
    data = JSON.parse(File.read(Rails.root.join('tmp') + 'data.json')) rescue {}
    resume_path = (public_path + data['filename']).to_s if data.length.positive?
    resume_path ||= Rails.root.join("public/Sumit-Kumar-Senior-Rails-Developer-Resume.pdf")
    puts "🔍 Validating: #{resume_path}"

    validator = Naukri::FileValidator.new(resume_path)
    if validator.valid?
      size_kb = (File.size(resume_path) / 1024.0).round(1)
      puts "✅ Valid! (#{size_kb} KB, type: #{validator.mime_type})"
    else
      puts "❌ Invalid:"
      validator.errors.each { |e| puts "   - #{e}" }
      exit 1
    end
  end
end
