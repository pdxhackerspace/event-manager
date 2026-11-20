require 'sidekiq'
require 'sidekiq-scheduler'

# Sidekiq configuration
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0') }

  # Load the schedule from config/sidekiq.yml
  config.on(:startup) do
    Sidekiq.schedule = YAML.load_file(File.expand_path('../sidekiq.yml', __dir__))[:schedule]
    SidekiqScheduler::Scheduler.instance.reload_schedule!
  end
end

# This file loads before the autoloader exists. Production then eager-loads
# app/ after initializers finish. Naming JobMetrics here raises
# "uninitialized constant JobMetrics" and the Sidekiq process exits before
# it can run jobs. after_initialize runs once eager load is done.
Rails.application.config.after_initialize do
  Sidekiq.configure_server do |config|
    # Per-job duration and failure stats for the Prometheus /metrics endpoint.
    config.server_middleware { |chain| chain.add JobMetrics::Middleware }
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0') }
end

# Configure Rails to use Sidekiq as the Active Job queue adapter
Rails.application.config.active_job.queue_adapter = :sidekiq
