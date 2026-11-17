# Prometheus Metrics

EventManager exposes application, database and Sidekiq statistics at `GET /metrics`
in the Prometheus text exposition format.

## Enabling and securing

The endpoint is **disabled** (returns `404`) until `METRICS_TOKEN` is set.

```bash
openssl rand -hex 32   # generate a token
METRICS_TOKEN=<token>  # set in the web container environment
```

Requests must send `Authorization: Bearer <token>`. A missing or wrong token gets `401`.
The token is not accepted as a query parameter, so it never ends up in access logs.
`/metrics` is exempt from the `req/ip` rate limit. Keep it off the public internet where
you can (restrict it at your proxy to the Prometheus host) in addition to the token.

```bash
curl -H "Authorization: Bearer $METRICS_TOKEN" https://events.example.org/metrics
```

### Prometheus scrape config

```yaml
scrape_configs:
  - job_name: event-manager
    metrics_path: /metrics
    scheme: https
    authorization:
      type: Bearer
      credentials_file: /etc/prometheus/event_manager_token
    static_configs:
      - targets: ['events.example.org']
```

## Metrics

All names are prefixed `event_manager_`.

| Area | Metrics |
|------|---------|
| Build | `build_info{version,rails,ruby,environment}`, `process_start_time_seconds` |
| Users | `users{role}`, `users_by_provider{provider}`, `users_can_create_events`, `users_created_last_24h` |
| Events | `events{status}`, `events_by_visibility{visibility}`, `events_drafts`, `events_recurring`, `events_exclusive_requests{exclusive_status}` |
| Occurrences | `occurrences{status}`, `occurrences_upcoming`, `occurrences_next_7d`, `locations`, `event_hosts`, `event_images` |
| RSVPs | `rsvps{status}`, `rsvps_guest`, `rsvps_checked_in`, `rsvps_no_shows` |
| Engagement | `favorites`, `favorite_changes{kind}`, `reminder_postings{platform}`, `social_credentials{platform}` |
| Storage | `active_storage_blobs`, `active_storage_bytes` |
| Database | `db_pool_connections{state}`, `db_query_seconds` |
| Sidekiq | `sidekiq_processed_total`, `sidekiq_failed_total`, `sidekiq_busy`, `sidekiq_processes`, `sidekiq_enqueued_jobs`, `sidekiq_scheduled_jobs`, `sidekiq_retry_jobs`, `sidekiq_dead_jobs`, `sidekiq_queue_size{queue}`, `sidekiq_queue_latency_seconds{queue}` |
| Sidekiq servers | `sidekiq_server_concurrency`, `sidekiq_server_busy`, `sidekiq_server_start_time_seconds` (labels `hostname`, `pid`) |
| Failures by type | `sidekiq_retry_jobs_by_class{job_class}`, `sidekiq_dead_jobs_by_class{job_class}`, `sidekiq_scheduled_jobs_by_class{job_class}` |
| Job history | `job_executions_total{job_class}`, `job_failures_total{job_class}`, `job_last_run_timestamp_seconds{job_class}`, `job_duration_seconds` histogram (`_bucket{job_class,le}`, `_sum`, `_count`) |
| Health | `collector_up{collector}` (`app`, `database`, `sidekiq`, `jobs`): `0` means that collector failed (e.g. Redis down); the rest of the scrape still succeeds |

### Job history

A Sidekiq server middleware (`JobMetrics::Middleware`) records each job's duration and
whether it raised, per job class, in the Redis hash `event_manager:job_metrics`. Counters
therefore cover all Sidekiq processes and survive restarts. Buckets are 0.1, 0.5, 1, 5, 15,
30, 60 and 300 seconds. To reset history, `DEL event_manager:job_metrics` in Redis.
Job counters only start accumulating after this version is deployed.

The label is `job_class` rather than `job` because Prometheus reserves `job` for the scrape config's `job_name` and would otherwise rename it to `exported_job`.

### Example queries

```promql
# Failure ratio per job over 1h
sum by (job_class) (increase(event_manager_job_failures_total[1h]))
  / sum by (job_class) (increase(event_manager_job_executions_total[1h]))

# p95 duration per job
histogram_quantile(0.95, sum by (job_class, le) (rate(event_manager_job_duration_seconds_bucket[1h])))

# Jobs stuck in retry, by type
event_manager_sidekiq_retry_jobs_by_class > 0

# Queue falling behind
event_manager_sidekiq_queue_latency_seconds > 60
```

Counts of users, events and RSVPs are computed from the database on each scrape; a scrape
interval of 30 to 60 seconds is recommended.
