# Operations Guide

Comprehensive guide for deploying and managing EventManager for a hackerspace (200-500 members).

## Table of Contents
- [Deployment Procedures](#deployment-procedures)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Database Maintenance](#database-maintenance)
- [Backup & Restore](#backup--restore)

---

## Deployment Procedures

### Initial Production Setup

**Prerequisites:**
- Linux server with Docker and Docker Compose installed
- Domain name pointed to your server
- SSL certificate (Cloudflare handles this automatically)
- GitHub access to pull Docker images

**1. Clone the repository:**
```bash
git clone git@github.com:romkey/pdxhackerspace-eventmanager.git
cd pdxhackerspace-eventmanager
```

**2. Create environment file:**
```bash
cp .env.production.example .env
```

**3. Configure environment variables:**
```bash
# Edit .env file with your production values
nano .env
```

Required variables:
```env
# Database
DATABASE_HOST=db
DATABASE_USER=eventmanager
DATABASE_PASSWORD=<generate-secure-password>
DATABASE_NAME=EventManager_production

# Rails
SECRET_KEY_BASE=<generate-with-rails-secret>
RAILS_ENV=production

# Redis
REDIS_URL=redis://redis:6379/0

# Authentication (if using Authentik/OAuth)
AUTHENTIK_CLIENT_ID=<your-client-id>
AUTHENTIK_CLIENT_SECRET=<your-secret>
AUTHENTIK_SITE_URL=https://auth.yourdomain.com
```

**Generate SECRET_KEY_BASE:**
```bash
docker run --rm ghcr.io/romkey/pdxhackerspace-eventmanager:latest \
  bundle exec rails secret
```

**4. Pull latest images:**
```bash
docker compose pull
```

**5. Start services:**
```bash
docker compose up -d
```

**6. Initialize database:**
```bash
# Run migrations
docker compose exec web bundle exec rails db:migrate

# Seed initial data
docker compose exec web bundle exec rails db:seed
```

**7. Create admin user:**
```bash
docker compose exec web bundle exec rails runner "
  User.create!(
    email: 'admin@yourhackerspace.org',
    password: 'ChangeMeImmediately123!',
    name: 'Admin',
    role: 'admin'
  )
"
```

**8. Configure site settings:**
- Login at `https://yourdomain.com`
- Navigate to Settings (admin only)
- Set organization name, contact info, etc.

### Updating to New Version

**Zero-downtime deployment process:**

**1. Pull new image:**
```bash
docker compose pull
```

**2. Check health before update:**
```bash
curl http://localhost:3000/health
```

**3. Run database migrations (if any):**
```bash
# Check if migrations are pending
docker compose run --rm web bundle exec rails db:migrate:status

# Run migrations
docker compose run --rm web bundle exec rails db:migrate RAILS_ENV=production
```

**4. Restart services:**
```bash
# Restart web and sidekiq with new image
docker compose up -d --no-deps --build web sidekiq
```

**5. Verify deployment:**
```bash
# Check health
curl http://localhost:3000/health

# Check logs
docker compose logs web --tail 50
docker compose logs sidekiq --tail 50
```

**6. Monitor for issues:**
```bash
# Watch logs for 2-3 minutes
docker compose logs -f web sidekiq
```

**Rollback procedure (if needed):**
```bash
# Pull previous version
docker compose pull

# Or specify version
docker pull ghcr.io/romkey/pdxhackerspace-eventmanager:v0.0.14-alpha

# Update docker-compose.yml to pin version
# Change: image: ghcr.io/romkey/pdxhackerspace-eventmanager:latest
# To: image: ghcr.io/romkey/pdxhackerspace-eventmanager:v0.0.14-alpha

# Restart
docker compose up -d
```

---

## Monitoring

### Health Check Endpoints

EventManager provides three health check endpoints:

**1. Liveness Probe** - Is the app running?
```bash
curl http://localhost:3000/health/liveness

# Response:
# {"status":"ok","timestamp":"2025-11-04T05:30:00Z"}
```

**2. Readiness Probe** - Is the app ready to serve traffic?
```bash
curl http://localhost:3000/health/readiness

# Response:
# {
#   "status":"ready",
#   "checks":{
#     "database":{"status":"ok","message":"Database connection successful"},
#     "redis":{"status":"ok","message":"Redis connection successful"},
#     "storage":{"status":"ok","message":"Storage accessible"}
#   },
#   "timestamp":"2025-11-04T05:30:00Z"
# }
```

**3. Detailed Health Check** - Full component status
```bash
curl http://localhost:3000/health

# Response includes Sidekiq stats, app version, etc.
```

### Docker Health Status

**Check all container health:**
```bash
docker compose ps

# Shows health status for each service:
# NAME                  STATUS
# eventmanager_db       Up (healthy)
# eventmanager_redis    Up (healthy)
# eventmanager_web      Up (healthy)
# eventmanager_sidekiq  Up (healthy)
```

### Monitoring Logs

**Real-time log monitoring:**
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f web
docker compose logs -f sidekiq
docker compose logs -f db
docker compose logs -f redis

# Last N lines
docker compose logs --tail 100 web

# With timestamps
docker compose logs -f -t web
```

**Log locations (persistent):**
```
./log/production.log     # Rails app logs
./log/sidekiq.log        # Sidekiq job logs (written by app)
```

### Metrics to Watch

**For a hackerspace (200-500 members):**

1. **Response Times** - Should be under 500ms for most requests
2. **Error Rate** - Should be near 0% (maybe 1-2 errors/day is fine)
3. **Database Connections** - Max 10-20 concurrent (very low usage)
4. **Memory Usage** - Web: ~200-400MB, Sidekiq: ~150-300MB
5. **Disk Usage** - Watch storage/ directory for uploaded images

**Quick health check script:**
```bash
#!/bin/bash
# save as check-health.sh

echo "=== Container Status ==="
docker compose ps

echo -e "\n=== Health Endpoints ==="
curl -s http://localhost:3000/health/liveness | jq .
curl -s http://localhost:3000/health | jq .

echo -e "\n=== Resource Usage ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo -e "\n=== Disk Usage ==="
du -sh ./storage ./log
df -h | grep -E '(Filesystem|/$)'
```

### Sidekiq Monitoring

**Web UI:**
- Access at: `https://yourdomain.com/sidekiq` (admin only)
- View queued, processing, and failed jobs
- Monitor scheduled job execution
- Retry failed jobs manually

**Command line:**
```bash
# Check Sidekiq process
docker compose exec sidekiq ps aux | grep sidekiq

# Check Redis connection
docker compose exec redis redis-cli ping

# View scheduled jobs
docker compose exec web bundle exec rails runner "
  require 'sidekiq/api'
  puts Sidekiq::ScheduledSet.new.map(&:display_class)
"

# View job statistics
docker compose exec web bundle exec rails runner "
  stats = Sidekiq::Stats.new
  puts 'Processed: ' + stats.processed.to_s
  puts 'Failed: ' + stats.failed.to_s
  puts 'Scheduled: ' + stats.scheduled_size.to_s
  puts 'Retry: ' + stats.retry_size.to_s
"
```

### Cloudflare Integration

Since you're behind Cloudflare:

**1. Enable Cloudflare Analytics:**
- Login to Cloudflare dashboard
- View traffic analytics, threat analysis
- Cache statistics
- Bandwidth savings

**2. Cloudflare Health Checks (optional):**
- Navigate to Traffic > Health Checks
- Add health check: `https://yourdomain.com/health/liveness`
- Set interval: 60 seconds
- Get email/webhook alerts on failures

**3. Monitor Cloudflare Cache:**
- Most static assets should be cached
- HTML pages should be mostly cache MISS (dynamic content)
- Images/CSS/JS should be cache HIT

---

## Troubleshooting

### Common Issues

#### 1. Application Won't Start

**Symptoms:**
- Container exits immediately
- "Connection refused" errors
- Health checks failing

**Diagnosis:**
```bash
# Check container logs
docker compose logs web

# Check if all environment variables are set
docker compose exec web env | grep -E '(SECRET_KEY_BASE|DATABASE|REDIS)'

# Test database connection
docker compose exec web bundle exec rails runner "
  ActiveRecord::Base.connection.execute('SELECT 1')
  puts 'Database: OK'
"

# Test Redis connection
docker compose exec web bundle exec rails runner "
  redis = Redis.new(url: ENV['REDIS_URL'])
  redis.ping
  puts 'Redis: OK'
"
```

**Solutions:**
- Missing `SECRET_KEY_BASE`: Generate and add to `.env`
- Database connection failed: Check `DATABASE_*` variables
- Redis connection failed: Check `REDIS_URL` and redis container status

#### 2. 500 Internal Server Error

**Diagnosis:**
```bash
# Check recent errors
docker compose logs web --tail 100 | grep -i error

# Check Rails log
docker compose exec web tail -100 /app/log/production.log

# Check for missing assets
docker compose exec web ls -la /app/public/assets/
```

**Common causes:**
- Missing asset precompilation
- Database migration not run
- Missing environment variable
- Disk full (check with `df -h`)

**Solutions:**
```bash
# Recompile assets
docker compose exec web bundle exec rails assets:precompile RAILS_ENV=production

# Run pending migrations
docker compose exec web bundle exec rails db:migrate RAILS_ENV=production

# Restart web server
docker compose restart web
```

#### 3. Sidekiq Jobs Not Running

**Symptoms:**
- Occurrences not being regenerated
- No job activity in Sidekiq web UI

**Diagnosis:**
```bash
# Check Sidekiq process
docker compose logs sidekiq

# Check if Sidekiq can reach Redis
docker compose exec sidekiq bundle exec rails runner "
  redis = Redis.new(url: ENV['REDIS_URL'])
  puts redis.ping
"

# Check scheduled jobs
docker compose exec sidekiq bundle exec rails runner "
  puts Sidekiq.schedule.inspect
"
```

**Solutions:**
```bash
# Restart Sidekiq
docker compose restart sidekiq

# Clear stuck jobs
docker compose exec web bundle exec rails runner "
  Sidekiq::Queue.new('default').clear
  Sidekiq::RetrySet.new.clear
  Sidekiq::ScheduledSet.new.clear
"

# Manually run the regeneration job
docker compose exec web bundle exec rails runner "
  RegenerateEventOccurrencesJob.perform_now
"
```

#### 4. Database Performance Issues

**Symptoms:**
- Slow page loads
- Timeout errors
- High database CPU

**Diagnosis:**
```bash
# Check database connections
docker compose exec db psql -U eventmanager -d EventManager_production -c "
  SELECT count(*) as connections FROM pg_stat_activity;
"

# Check slow queries (if pg_stat_statements enabled)
docker compose exec db psql -U eventmanager -d EventManager_production -c "
  SELECT query, calls, mean_exec_time 
  FROM pg_stat_statements 
  ORDER BY mean_exec_time DESC 
  LIMIT 10;
"

# Check table sizes
docker compose exec db psql -U eventmanager -d EventManager_production -c "
  SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) 
  FROM pg_tables 
  WHERE schemaname = 'public' 
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"
```

**Solutions:**
```bash
# Analyze database (updates statistics for query planner)
docker compose exec db psql -U eventmanager -d EventManager_production -c "ANALYZE;"

# Vacuum database (reclaims space)
docker compose exec db psql -U eventmanager -d EventManager_production -c "VACUUM ANALYZE;"

# Add missing indices (see DATABASE_MAINTENANCE.md)
```

#### 5. Disk Space Issues

**Diagnosis:**
```bash
# Check disk usage
df -h

# Find large directories
du -sh ./storage/* ./log/* | sort -h

# Check old logs
ls -lh ./log/
```

**Solutions:**
```bash
# Rotate logs
docker compose exec web bundle exec rails log:clear

# Or manually truncate
: > ./log/production.log

# Clean old uploads (be careful!)
# Find files older than 90 days
find ./storage -type f -mtime +90 -exec ls -lh {} \;

# Archive old images
tar -czf storage-backup-$(date +%Y%m%d).tar.gz ./storage
mv storage-backup-*.tar.gz /backup/location/

# Set up log rotation with logrotate
```

#### 6. Authentication Issues (Authentik/OAuth)

**Symptoms:**
- "Redirect URI mismatch" errors
- Users can't log in via OAuth
- Authentication loops

**Diagnosis:**
```bash
# Check OAuth configuration
docker compose exec web bundle exec rails runner "
  puts 'OAuth configured:' + ENV['AUTHENTIK_CLIENT_ID'].present?.to_s
  puts 'Site URL:' + ENV['AUTHENTIK_SITE_URL']
"

# Check logs for OAuth errors
docker compose logs web | grep -i oauth
docker compose logs web | grep -i authentik
```

**Solutions:**
- Verify redirect URI in Authentik matches your domain
- Check `AUTHENTIK_SITE_URL` is correct
- Ensure `AUTHENTIK_CLIENT_ID` and `AUTHENTIK_CLIENT_SECRET` are set
- Check Authentik server logs for errors

---

## Database Maintenance

### Regular Maintenance Tasks

**Weekly:**
```bash
# Analyze database statistics
docker compose exec db psql -U eventmanager -d EventManager_production -c "ANALYZE;"
```

**Monthly:**
```bash
# Full vacuum and analyze
docker compose exec db psql -U eventmanager -d EventManager_production -c "VACUUM ANALYZE;"

# Check for bloat (optional)
docker compose exec db psql -U eventmanager -d EventManager_production -c "
  SELECT schemaname, tablename, 
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
  FROM pg_tables
  WHERE schemaname = 'public'
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"
```

**Quarterly:**
```bash
# Reindex (only if you suspect index corruption)
docker compose exec db psql -U eventmanager -d EventManager_production -c "REINDEX DATABASE EventManager_production;"
```

### Database Optimization for Hackerspace Scale

**Expected data volumes (200-500 members):**
- Users: 200-500 records
- Events: 50-200 events total
- Event Occurrences: 250-1,000 records
- Event Hosts: 100-400 records
- Event Journals: 500-2,000 records

**Database size estimate:** 50-200 MB

At this scale, **database performance is not a concern**. The indices we've added are sufficient.

**What you DON'T need:**
- Connection pooling (PgBouncer)
- Read replicas
- Database sharding
- Query caching layers

### Cleaning Old Data

**Archive old event occurrences (optional):**
```bash
# Find occurrences older than 1 year
docker compose exec web bundle exec rails runner "
  old_occurrences = EventOccurrence.where('occurs_at < ?', 1.year.ago)
  puts 'Found ' + old_occurrences.count.to_s + ' old occurrences'
"

# Archive to CSV before deleting
docker compose exec web bundle exec rails runner "
  require 'csv'
  occurrences = EventOccurrence.where('occurs_at < ?', 1.year.ago).includes(:event)
  CSV.open('/app/log/archived_occurrences_#{Date.today}.csv', 'w') do |csv|
    csv << ['ID', 'Event Title', 'Occurs At', 'Status']
    occurrences.each do |occ|
      csv << [occ.id, occ.event.title, occ.occurs_at, occ.status]
    end
  end
  puts 'Archived to log/archived_occurrences_#{Date.today}.csv'
"

# Delete old occurrences
docker compose exec web bundle exec rails runner "
  EventOccurrence.where('occurs_at < ?', 1.year.ago).destroy_all
  puts 'Old occurrences deleted'
"
```

### Database Backups

See [Backup & Restore](#backup--restore) section.

---

## Backup & Restore

### What to Backup

1. **Database** (critical)
2. **Uploaded files** (`./storage` directory)
3. **Environment configuration** (`.env` file)
4. **Log files** (optional, for forensics)

### Automated Daily Backups

**Create backup script:**
```bash
#!/bin/bash
# save as /usr/local/bin/backup-eventmanager.sh

# Configuration
BACKUP_DIR="/backup/eventmanager"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Create backup directory
mkdir -p $BACKUP_DIR

# Database backup
echo "Backing up database..."
docker compose exec -T db pg_dump -U eventmanager EventManager_production | \
  gzip > $BACKUP_DIR/database_$DATE.sql.gz

# Storage backup
echo "Backing up uploaded files..."
tar -czf $BACKUP_DIR/storage_$DATE.tar.gz ./storage

# Environment backup
echo "Backing up configuration..."
cp .env $BACKUP_DIR/env_$DATE

# Clean old backups
echo "Cleaning backups older than $RETENTION_DAYS days..."
find $BACKUP_DIR -type f -name "database_*.sql.gz" -mtime +$RETENTION_DAYS -delete
find $BACKUP_DIR -type f -name "storage_*.tar.gz" -mtime +$RETENTION_DAYS -delete
find $BACKUP_DIR -type f -name "env_*" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $DATE"
```

**Make executable:**
```bash
chmod +x /usr/local/bin/backup-eventmanager.sh
```

**Set up cron job:**
```bash
sudo crontab -e

# Add line (runs at 3 AM daily):
0 3 * * * /usr/local/bin/backup-eventmanager.sh >> /var/log/eventmanager-backup.log 2>&1
```

### Manual Backup

**Database only:**
```bash
# Create backup
docker compose exec -T db pg_dump -U eventmanager EventManager_production > \
  backup_$(date +%Y%m%d).sql

# Compress
gzip backup_$(date +%Y%m%d).sql
```

**Full backup:**
```bash
# Stop services
docker compose down

# Backup everything
tar -czf eventmanager-full-backup-$(date +%Y%m%d).tar.gz \
  docker-compose.yml \
  .env \
  storage/ \
  log/

# Restart
docker compose up -d
```

### Restore from Backup

**1. Stop services:**
```bash
docker compose down
```

**2. Restore database:**
```bash
# Start only database
docker compose up -d db

# Wait for database to be ready
sleep 10

# Drop existing database
docker compose exec db psql -U eventmanager -c "DROP DATABASE IF EXISTS EventManager_production;"

# Create new database
docker compose exec db psql -U eventmanager -c "CREATE DATABASE EventManager_production;"

# Restore from backup
gunzip -c database_20251104.sql.gz | \
  docker compose exec -T db psql -U eventmanager EventManager_production
```

**3. Restore storage files:**
```bash
tar -xzf storage_20251104.tar.gz
```

**4. Restart all services:**
```bash
docker compose up -d
```

**5. Verify:**
```bash
# Check health
curl http://localhost:3000/health

# Check data
docker compose exec web bundle exec rails runner "
  puts 'Users: ' + User.count.to_s
  puts 'Events: ' + Event.count.to_s
  puts 'Occurrences: ' + EventOccurrence.count.to_s
"
```

### Off-site Backup (Recommended)

**Option 1: rsync to remote server:**
```bash
# Add to backup script
rsync -avz --delete /backup/eventmanager/ \
  user@backup-server:/remote/backup/eventmanager/
```

**Option 2: S3/B2/Backblaze:**
```bash
# Install rclone
# Configure once: rclone config

# Add to backup script
rclone sync /backup/eventmanager/ remote:eventmanager-backups/
```

**Option 3: Borg Backup (encrypted):**
```bash
# Install borg
apt-get install borgbackup

# Initialize repository (once)
borg init --encryption=repokey /backup/borg-eventmanager

# Add to backup script
borg create /backup/borg-eventmanager::'{now}' \
  ./storage \
  ./.env \
  --stats --progress

# Prune old backups
borg prune --keep-daily=7 --keep-weekly=4 --keep-monthly=6 \
  /backup/borg-eventmanager
```

### Disaster Recovery Plan

**Scenario: Complete server failure**

**Recovery steps:**

1. **Provision new server** (same specs)
2. **Install Docker and Docker Compose**
3. **Clone repository**
4. **Restore `.env` file from backup**
5. **Pull Docker images**: `docker compose pull`
6. **Start database**: `docker compose up -d db`
7. **Restore database from backup** (see above)
8. **Restore storage files** from backup
9. **Start all services**: `docker compose up -d`
10. **Update DNS** to point to new server
11. **Verify** with health checks and manual testing

**Recovery Time Objective (RTO):** 2-4 hours
**Recovery Point Objective (RPO):** 24 hours (with daily backups)

---

## Emergency Contacts

**Keep this information updated:**

```
Primary Admin: _______________
Phone: _______________
Email: _______________

Backup Admin: _______________
Phone: _______________
Email: _______________

Hosting Provider: _______________
Support: _______________

Domain Registrar: _______________
Support: _______________
```

---

## Next Steps

- Review [SECURITY.md](SECURITY.md) for security hardening
- Configure [monitoring alerts](#monitoring)
- Set up [automated backups](#automated-daily-backups)
- Test [disaster recovery](#disaster-recovery-plan) once
- Review [SIDEKIQ.md](SIDEKIQ.md) for background job management


