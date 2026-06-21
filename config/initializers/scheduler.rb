require 'rufus-scheduler'
require 'rake'

Rails.application.load_tasks

scheduler = Rufus::Scheduler.new
# scheduler.logger = Rails.logger
# scheduler.cron '0 9,13,17 * * *' do
# scheduler.cron '10 * * * *' do
scheduler.every '10m' do
  Rails.logger.info "=== Scheduler started #{Time.current} ==="

  Rake::Task['naukri:refresh_profile'].reenable
  Rake::Task['naukri:refresh_profile'].invoke

  Rails.logger.info "=== Scheduler completed ==="
end