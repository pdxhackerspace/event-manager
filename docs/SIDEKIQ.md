# Sidekiq Background Jobs

EventManager uses [Sidekiq](https://sidekiq.org/) for background job processing, powered by Redis.

## Features

### Automatic Occurrence Regeneration

The `RegenerateEventOccurrencesJob` runs daily at 2 AM to automatically generate new occurrences for recurring events. This ensures your calendar always shows upcoming events without manual intervention.

**How it works:**
1. Finds all active recurring events
2. Checks if they have fewer upcoming occurrences than their `max_occurrences` setting
3. Generates additional occurrences to maintain the target count
4. Logs activity to Rails logs

## Configuration

### Scheduler Settings

Configured in `config/sidekiq.yml`:

```yaml
:schedule:
  regenerate_event_occurrences:
    cron: '0 2 * * *'  # Daily at 2 AM
    class: RegenerateEventOccurrencesJob
```

To change the schedule, modify the `cron` expression. Examples:
- `'0 */6 * * *'` - Every 6 hours
- `'0 0 * * 0'` - Weekly on Sunday at midnight
- `'*/30 * * * *'` - Every 30 minutes

### Redis Configuration

Connection URL is configured via the `REDIS_URL` environment variable:
- **Development:** `redis://redis:6379/0` (Docker container)
- **Production:** Set via environment variable or defaults to `redis://redis:6379/0`

## Monitoring

### Sidekiq Web UI

Access the Sidekiq web dashboard at `/sidekiq` (admin users only).

Features:
- View queued, processing, and completed jobs
- Monitor job statistics and performance
- Manage scheduled jobs
- View and retry failed jobs
- See real-time metrics

### Logs

Monitor Sidekiq activity in your Rails logs:

```bash
# Development (Docker)
docker compose -f docker-compose.dev.yml logs sidekiq --follow

# View job execution logs
docker compose -f docker-compose.dev.yml logs web --follow | grep RegenerateEventOccurrencesJob
```

## Docker Setup

### Development

The `docker-compose.dev.yml` includes:
- **redis** service (Redis 7 Alpine)
- **sidekiq** service (runs `sidekiq -C config/sidekiq.yml`)

```bash
# Start all services including Sidekiq
docker compose -f docker-compose.dev.yml up -d

# View Sidekiq logs
docker compose -f docker-compose.dev.yml logs sidekiq -f

# Restart Sidekiq
docker compose -f docker-compose.dev.yml restart sidekiq
```

### Production

The production `docker-compose.yml` includes the same services using the production Docker image.

Redis data is persisted in the `redis_data` volume.

## Manual Job Execution

### Run Job Immediately

```bash
# Development (Docker)
docker compose -f docker-compose.dev.yml exec web bundle exec rails runner "RegenerateEventOccurrencesJob.perform_now"

# Production
docker compose exec web bundle exec rails runner "RegenerateEventOccurrencesJob.perform_now"
```

### Queue Job for Async Execution

```ruby
# In Rails console
RegenerateEventOccurrencesJob.perform_later

# Or with Active Job
RegenerateEventOccurrencesJob.set(wait: 1.hour).perform_later
```

## Troubleshooting

### Sidekiq Not Starting

**Check Redis connection:**
```bash
# Development
docker compose -f docker-compose.dev.yml exec redis redis-cli ping
# Should return: PONG
```

**Check Sidekiq logs:**
```bash
docker compose -f docker-compose.dev.yml logs sidekiq
```

### Jobs Not Running

1. **Verify scheduler is loaded:**
   - Check Sidekiq logs for "Scheduling regenerate_event_occurrences" on startup
   - Visit `/sidekiq/recurring-jobs` to see scheduled jobs

2. **Check job configuration:**
   - Ensure `config/sidekiq.yml` is present and readable
   - Verify cron expression is valid

3. **Test job manually:**
   ```bash
   docker compose -f docker-compose.dev.yml exec web bundle exec rails runner "RegenerateEventOccurrencesJob.perform_now"
   ```

### Failed Jobs

1. Visit `/sidekiq/retries` to see failed jobs
2. Check error messages and stack traces
3. Fix underlying issues
4. Retry failed jobs from the web UI or:
   ```ruby
   # In Rails console
   Sidekiq::RetrySet.new.retry_all
   ```

## Production Considerations

### External Redis

For production, consider using a managed Redis service:

**AWS ElastiCache:**
```yaml
# docker-compose.yml
environment:
  REDIS_URL: redis://your-elasticache-endpoint:6379/0
```

**Redis Cloud:**
```yaml
environment:
  REDIS_URL: rediss://default:password@your-endpoint:port
```

### Monitoring

Consider adding monitoring tools:
- [Sidekiq Enterprise](https://sidekiq.org/products/enterprise.html) - Advanced monitoring
- [New Relic](https://newrelic.com/) - APM with Sidekiq support
- [Datadog](https://www.datadoghq.com/) - Infrastructure monitoring

### Scaling

To handle more jobs, scale Sidekiq workers:

```yaml
# docker-compose.yml
sidekiq:
  command: bundle exec sidekiq -C config/sidekiq.yml -c 10  # 10 concurrent workers
```

Or run multiple Sidekiq instances:

```bash
docker compose up -d --scale sidekiq=3
```

## Adding New Jobs

1. **Create job class:**
   ```ruby
   # app/jobs/my_job.rb
   class MyJob < ApplicationJob
     queue_as :default

     def perform(*args)
       # Job logic here
     end
   end
   ```

2. **Add schedule (if recurring):**
   ```yaml
   # config/sidekiq.yml
   :schedule:
     my_job:
       cron: '0 3 * * *'  # Daily at 3 AM
       class: MyJob
   ```

3. **Queue the job:**
   ```ruby
   MyJob.perform_later(arg1, arg2)
   ```

## References

- [Sidekiq Documentation](https://github.com/sidekiq/sidekiq/wiki)
- [sidekiq-scheduler](https://github.com/sidekiq-scheduler/sidekiq-scheduler)
- [Cron Expression Syntax](https://crontab.guru/)
- [Redis Documentation](https://redis.io/documentation)

