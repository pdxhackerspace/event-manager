# frozen_string_literal: true

# Per-job-class execution statistics, recorded by a Sidekiq server middleware
# and stored in a single Redis hash so every Sidekiq process and the web
# process share one view. Exposed through the Prometheus /metrics endpoint.
#
# Hash fields: "<job class>|count", "|failures", "|duration_sum",
# "|bucket:<le>" (cumulative histogram buckets, seconds) and "|last_run".
module JobMetrics
  KEY = 'event_manager:job_metrics'
  BUCKETS = [0.1, 0.5, 1, 5, 15, 30, 60, 300].freeze

  # Sidekiq server middleware.
  class Middleware
    include Sidekiq::ServerMiddleware

    def call(_worker, job, _queue)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      failed = false
      yield
    rescue Exception # rubocop:disable Lint/RescueException
      failed = true
      raise
    ensure
      JobMetrics.record(job['wrapped'] || job['class'],
                        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, failed: failed)
    end
  end

  def self.record(job_class, duration, failed: false)
    name = job_class.to_s
    Sidekiq.redis do |redis|
      redis.pipelined do |pipe|
        pipe.hincrby(KEY, "#{name}|count", 1)
        pipe.hincrby(KEY, "#{name}|failures", 1) if failed
        pipe.hincrbyfloat(KEY, "#{name}|duration_sum", duration)
        pipe.hset(KEY, "#{name}|last_run", Time.now.to_f)
        BUCKETS.each { |le| pipe.hincrby(KEY, "#{name}|bucket:#{le}", 1) if duration <= le }
      end
    end
  rescue StandardError => e
    Rails.logger.warn("JobMetrics: could not record #{name}: #{e.message}")
  end

  # => { 'FooJob' => { 'count' => '3', 'failures' => '1', ... } }
  def self.snapshot
    raw = Sidekiq.redis { |redis| redis.hgetall(KEY) }
    raw.each_with_object(Hash.new { |h, k| h[k] = {} }) do |(field, value), out|
      name, stat = field.split('|', 2)
      out[name][stat] = value
    end
  end
end
