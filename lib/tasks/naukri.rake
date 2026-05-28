# lib/tasks/naukri.rake
namespace :naukri do
  desc "Upload resume to Naukri.com (RESUME_PATH=... optional)"
  task upload_resume: :environment do
    resume_path = ENV["RESUME_PATH"]
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

  desc "Upload resume AND refresh profile visibility"
  task upload_and_refresh: :environment do
    resume_path = ENV["RESUME_PATH"]
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
    resume_path = ENV["RESUME_PATH"]
    puts "⏰ Enqueueing NaukriResumeUploadJob..."
    NaukriResumeUploadJob.perform_later(resume_path)
    puts "✅ Job queued! Check Sidekiq dashboard."
  end

  desc "Validate resume file before uploading"
  task validate_resume: :environment do
    resume_path = ENV["RESUME_PATH"] || Rails.application.config_for(:naukri)[:resume_path]
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
