# app/jobs/naukri_resume_upload_job.rb
class NaukriResumeUploadJob < ApplicationJob
  queue_as :default

  # Retry up to 3 times with exponential backoff (5s, 25s, 125s)
  retry_on StandardError,        wait: :exponentially_longer, attempts: 3
  retry_on Faraday::TimeoutError, wait: 10.seconds,           attempts: 3

  # Don't retry on bad credentials
  discard_on ArgumentError

  def perform(resume_path = nil, options = {})
    logger.info "[NaukriResumeUploadJob] 🚀 Job started at #{Time.current}"

    uploader = Naukri::Uploader.new

    result = if options[:with_refresh]
               uploader.run_with_refresh(resume_path)
             else
               uploader.run(resume_path)
             end

    if result.success?
      logger.info "[NaukriResumeUploadJob] ✅ Job completed successfully"
      notify_success(result) if options[:notify]
    else
      logger.error "[NaukriResumeUploadJob] ❌ Job failed: #{result.error}"
      raise "Naukri upload failed: #{result.error}"
    end
  end

  private

  def notify_success(result)
    # Hook: add email/Slack notification here if needed
    logger.info "[NaukriResumeUploadJob] 📬 Notification sent"
  end
end
