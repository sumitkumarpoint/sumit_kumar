require 'rufus-scheduler'
require 'rake'

Rails.application.load_tasks

scheduler = Rufus::Scheduler.new
# scheduler.logger = Rails.logger
# scheduler.cron '0 9,13,17 * * *' do
# scheduler.cron '10 * * * *' do
scheduler.every '10m' do
  Rails.logger.info "=== Scheduler started #{Time.current} ==="

  Rake::Task['naukri:upload_resume'].reenable
  Rake::Task['naukri:upload_resume'].invoke

  Rails.logger.info "=== Scheduler completed ==="
end