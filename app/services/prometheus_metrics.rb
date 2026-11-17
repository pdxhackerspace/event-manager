# frozen_string_literal: true

# Renders application, database and Sidekiq statistics in the Prometheus text
# exposition format (version 0.0.4). Each collector is isolated so one failing
# dependency (e.g. Redis down) does not take the whole scrape down; failures
# are reported through event_manager_collector_up instead.
class PrometheusMetrics
  CONTENT_TYPE = 'text/plain; version=0.0.4; charset=utf-8'
  PROCESS_START = Time.now.to_i

  def initialize
    @lines = []
    @collector_status = {}
  end

  def render
    run(:app) { collect_app }
    run(:database) { collect_database }
    run(:sidekiq) { collect_sidekiq }
    run(:jobs) { collect_job_metrics }
    collector_status
    "#{@lines.join("\n")}\n"
  end

  private

  def run(name)
    yield
    @collector_status[name] = 1
  rescue StandardError => e
    Rails.logger.warn("PrometheusMetrics: #{name} collector failed: #{e.message}")
    @collector_status[name] = 0
  end

  def collector_status
    metric('event_manager_collector_up', 'gauge', '1 if the metrics collector succeeded, 0 if it failed.') do
      @collector_status.each { |name, up| sample('event_manager_collector_up', up, collector: name) }
    end
  end

  # --- collectors -----------------------------------------------------------

  def collect_app
    metric('event_manager_build_info', 'gauge', 'Application version; always 1.') do
      sample('event_manager_build_info', 1, version: ENV.fetch('APP_VERSION', Rails.root.join('VERSION').read.strip),
                                            rails: Rails.version, ruby: RUBY_VERSION, environment: Rails.env)
    end
    metric('event_manager_process_start_time_seconds', 'gauge', 'Start time of this web process (unix time).') do
      sample('event_manager_process_start_time_seconds', PROCESS_START)
    end
  end

  def collect_database
    users
    events
    occurrences
    rsvps
    engagement
    infrastructure
    database_pool
  end

  def users
    grouped('event_manager_users', 'Users by role.', User.group(:role).count, :role)
    gauge('event_manager_users_can_create_events', 'Users allowed to create events.',
          User.where(can_create_events: true).count)
    grouped('event_manager_users_by_provider', 'Users by sign-in provider (none = password).',
            User.group(:provider).count.transform_keys { |k| k.presence || 'none' }, :provider)
    gauge('event_manager_users_created_last_24h', 'Users created in the last 24 hours.',
          User.where(created_at: 24.hours.ago..).count)
  end

  def events
    grouped('event_manager_events', 'Events by status.', Event.group(:status).count, :status)
    grouped('event_manager_events_by_visibility', 'Events by visibility.', Event.group(:visibility).count, :visibility)
    gauge('event_manager_events_drafts', 'Events that are drafts.', Event.drafts.count)
    gauge('event_manager_events_recurring', 'Events with a recurrence rule.', Event.where.not(recurrence_rule: [nil, '']).count)
    grouped('event_manager_events_exclusive_requests', 'Events by exclusive-use request status.',
            Event.group(:exclusive_status).count, :exclusive_status)
  end

  def occurrences
    grouped('event_manager_occurrences', 'Event occurrences by status.', EventOccurrence.group(:status).count, :status)
    gauge('event_manager_occurrences_upcoming', 'Upcoming event occurrences.', EventOccurrence.where(occurs_at: Time.current..).count)
    gauge('event_manager_occurrences_next_7d', 'Occurrences scheduled in the next 7 days.',
          EventOccurrence.where(occurs_at: Time.current..7.days.from_now).count)
    gauge('event_manager_locations', 'Locations.', Location.count)
    gauge('event_manager_event_hosts', 'Event host assignments.', EventHost.count)
    gauge('event_manager_event_images', 'Event images.', EventImage.count)
  end

  def rsvps
    grouped('event_manager_rsvps', 'RSVPs by status.', Rsvp.group(:status).count, :status)
    gauge('event_manager_rsvps_guest', 'Active RSVPs from guests without an account.', Rsvp.active.guests.count)
    gauge('event_manager_rsvps_checked_in', 'RSVPs checked in.', Rsvp.where.not(checked_in_at: nil).count)
    gauge('event_manager_rsvps_no_shows', 'RSVPs recorded as no-shows.', Rsvp.where(attended: false).count)
  end

  def engagement
    gauge('event_manager_favorites', 'Favorites (follows).', Favorite.count)
    grouped('event_manager_favorite_changes', 'Favorite change records awaiting cleanup, by kind.',
            FavoriteChange.group(:kind).count, :kind)
    grouped('event_manager_reminder_postings', 'Active social/Slack reminder postings by platform.',
            ReminderPosting.active.group(:platform).count, :platform)
    grouped('event_manager_social_credentials', 'Configured social credentials by platform.',
            SocialCredential.group(:platform).count, :platform)
  end

  def infrastructure
    gauge('event_manager_active_storage_blobs', 'Active Storage blobs.', ActiveStorage::Blob.count)
    gauge('event_manager_active_storage_bytes', 'Total bytes of Active Storage blobs.', ActiveStorage::Blob.sum(:byte_size))
  end

  def database_pool
    stat = ActiveRecord::Base.connection_pool.stat
    metric('event_manager_db_pool_connections', 'ActiveRecord connection pool state of this process.', 'gauge') do
      %i[size connections busy idle waiting].each { |k| sample('event_manager_db_pool_connections', stat[k], state: k) }
    end
    metric('event_manager_db_query_seconds', 'Time to run SELECT 1 against the database.', 'gauge') do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.connection.execute('SELECT 1')
      sample('event_manager_db_query_seconds', Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end
  end

  def collect_sidekiq
    stats = Sidekiq::Stats.new
    gauge('event_manager_sidekiq_processed_total', 'Jobs processed since stats were last reset.', stats.processed, type: 'counter')
    gauge('event_manager_sidekiq_failed_total', 'Jobs failed since stats were last reset.', stats.failed, type: 'counter')
    gauge('event_manager_sidekiq_busy', 'Jobs currently executing.', stats.workers_size)
    gauge('event_manager_sidekiq_processes', 'Running Sidekiq server processes.', stats.processes_size)
    gauge('event_manager_sidekiq_scheduled_jobs', 'Jobs scheduled for the future.', stats.scheduled_size)
    gauge('event_manager_sidekiq_retry_jobs', 'Jobs waiting to be retried.', stats.retry_size)
    gauge('event_manager_sidekiq_dead_jobs', 'Jobs in the dead set.', stats.dead_size)
    gauge('event_manager_sidekiq_enqueued_jobs', 'Jobs enqueued across all queues.', stats.enqueued)
    grouped('event_manager_sidekiq_queue_size', 'Enqueued jobs per queue.', stats.queues, :queue)
    grouped('event_manager_sidekiq_queue_latency_seconds', 'Age of the oldest job per queue.',
            Sidekiq::Queue.all.to_h { |q| [q.name, q.latency] }, :queue)
    sidekiq_servers
    sidekiq_sets
  end

  def sidekiq_servers
    processes = Sidekiq::ProcessSet.new.to_a
    metric('event_manager_sidekiq_server_concurrency', 'Thread concurrency per Sidekiq server.', 'gauge') do
      processes.each { |p| sample('event_manager_sidekiq_server_concurrency', p['concurrency'], hostname: p['hostname'], pid: p['pid']) }
    end
    metric('event_manager_sidekiq_server_busy', 'Busy threads per Sidekiq server.', 'gauge') do
      processes.each { |p| sample('event_manager_sidekiq_server_busy', p['busy'], hostname: p['hostname'], pid: p['pid']) }
    end
    metric('event_manager_sidekiq_server_start_time_seconds', 'Sidekiq server start time (unix).', 'gauge') do
      processes.each { |p| sample('event_manager_sidekiq_server_start_time_seconds', p['started_at'], hostname: p['hostname'], pid: p['pid']) }
    end
  end

  # Retry and dead sets broken down by job class show which job types fail.
  def sidekiq_sets
    grouped('event_manager_sidekiq_retry_jobs_by_class', 'Jobs awaiting retry by job class.',
            tally_set(Sidekiq::RetrySet.new), :job)
    grouped('event_manager_sidekiq_dead_jobs_by_class', 'Dead jobs by job class.',
            tally_set(Sidekiq::DeadSet.new), :job)
    grouped('event_manager_sidekiq_scheduled_jobs_by_class', 'Scheduled jobs by job class.',
            tally_set(Sidekiq::ScheduledSet.new), :job)
  end

  def tally_set(set)
    set.each_with_object(Hash.new(0)) { |entry, h| h[entry.display_class] += 1 }
  end

  def collect_job_metrics
    data = JobMetrics.snapshot
    counter_by_job('event_manager_job_executions_total', 'Job executions by class.', data, 'count')
    counter_by_job('event_manager_job_failures_total', 'Job executions that raised, by class.', data, 'failures')
    metric('event_manager_job_last_run_timestamp_seconds', 'Unix time a job class last ran.', 'gauge') do
      data.each { |job, s| sample('event_manager_job_last_run_timestamp_seconds', s['last_run'].to_f, job: job) }
    end
    job_histogram(data)
  end

  def counter_by_job(name, help, data, stat)
    metric(name, help, 'counter') do
      data.each { |job, s| sample(name, s[stat].to_i, job: job) }
    end
  end

  def job_histogram(data)
    name = 'event_manager_job_duration_seconds'
    metric(name, 'Job execution duration by class.', 'histogram') do
      data.each do |job, s|
        JobMetrics::BUCKETS.each { |le| sample("#{name}_bucket", s["bucket:#{le}"].to_i, job: job, le: le) }
        sample("#{name}_bucket", s['count'].to_i, job: job, le: '+Inf')
        sample("#{name}_sum", s['duration_sum'].to_f, job: job)
        sample("#{name}_count", s['count'].to_i, job: job)
      end
    end
  end

  # --- rendering helpers ----------------------------------------------------

  def metric(name, help, type = 'gauge')
    @lines << "# HELP #{name} #{help}" << "# TYPE #{name} #{type}"
    yield
  end

  def gauge(name, help, value, type: 'gauge')
    metric(name, help, type) { sample(name, value) }
  end

  def grouped(name, help, counts, label)
    metric(name, help) { counts.each { |key, value| sample(name, value, label => key) } }
  end

  def sample(name, value, **labels)
    rendered = labels.map { |k, v| %(#{k}="#{escape(v)}") }.join(',')
    @lines << "#{name}#{"{#{rendered}}" if rendered.present?} #{format_value(value)}"
  end

  def escape(value)
    value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\n", '\\n')
  end

  def format_value(value)
    value.is_a?(Float) ? format('%.6f', value).sub(/\.?0+\z/, '') : value.to_i.to_s
  end
end
