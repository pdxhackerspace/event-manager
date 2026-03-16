# Debugging Guide

This document contains helpful commands and procedures for debugging the EventManager application.

## Table of Contents

- [Running Tests and Lint](#running-tests-and-lint)
- [Rails Console Access](#rails-console-access)
- [Rake Tasks Reference](#rake-tasks-reference)
- [Occurrence Management](#occurrence-management)
- [DST Issues](#dst-daylight-saving-time-issues)
- [User Account Debugging](#user-account-debugging)
- [Event Debugging](#event-debugging)
- [Occurrence Debugging](#occurrence-debugging)
- [Sidekiq / Background Jobs](#sidekiq--background-jobs)
- [Database Queries](#database-queries)
- [Timezone Debugging](#timezone-debugging)
- [Common Issues](#common-issues)

## Running Tests and Lint

All development work uses Docker. Make sure containers are running first:

```bash
# Start test containers (if not already running)
docker-compose -f docker-compose.test.yml up -d
```

### Running the Full Test Suite

```bash
docker-compose -f docker-compose.test.yml run --rm app bundle exec rspec
```

### Running Specific Tests

```bash
# Run a specific test file
docker-compose -f docker-compose.test.yml run --rm app bundle exec rspec spec/models/event_spec.rb

# Run a specific test by line number
docker-compose -f docker-compose.test.yml run --rm app bundle exec rspec spec/models/event_spec.rb:42

# Run tests matching a pattern
docker-compose -f docker-compose.test.yml run --rm app bundle exec rspec --pattern "spec/models/*_spec.rb"

# Run with documentation format (verbose output)
docker-compose -f docker-compose.test.yml run --rm app bundle exec rspec --format documentation
```

### Running Rubocop (Lint)

```bash
# Run Rubocop on all files
docker-compose -f docker-compose.test.yml run --rm app bundle exec rubocop

# Run on specific files
docker-compose -f docker-compose.test.yml run --rm app bundle exec rubocop app/models/event.rb

# Auto-fix safe corrections
docker-compose -f docker-compose.test.yml run --rm app bundle exec rubocop -a

# Auto-fix all corrections (including unsafe)
docker-compose -f docker-compose.test.yml run --rm app bundle exec rubocop -A
```

### Pre-Push Checklist

Before pushing changes, run:

```bash
# 1. Run all tests
docker-compose -f docker-compose.test.yml run --rm app bundle exec rspec

# 2. Run Rubocop
docker-compose -f docker-compose.test.yml run --rm app bundle exec rubocop

# 3. If Rubocop finds issues, auto-fix them
docker-compose -f docker-compose.test.yml run --rm app bundle exec rubocop -A

# 4. Re-run tests after auto-fix to make sure nothing broke
docker-compose -f docker-compose.test.yml run --rm app bundle exec rspec
```

### Cleaning Up Docker

```bash
# Stop containers
docker-compose -f docker-compose.test.yml down

# Remove volumes (clears database - useful if gems are out of sync)
docker-compose -f docker-compose.test.yml down -v

# Rebuild containers (after Gemfile changes)
docker-compose -f docker-compose.test.yml build

# Force reinstall gems
docker-compose -f docker-compose.test.yml run --rm app bundle install
```

## Rails Console Access

```bash
# Production
docker exec -it eventmanager_app_1 rails console

# Development/Test
docker-compose -f docker-compose.test.yml run --rm app rails console
```

## Rake Tasks Reference

All rake tasks can be run with:
```bash
# Production
docker exec -it eventmanager_app_1 rails <task_name>

# Development/Test
docker-compose -f docker-compose.test.yml run --rm app rails <task_name>
```

### DST / Timezone Correction Tasks

| Task | Description |
|------|-------------|
| `events:full_dst_fix` | **Recommended** - Runs both duplicate cleanup and time correction |
| `events:clean_duplicate_occurrences` | Removes duplicate occurrences on the same day (keeps correct time) |
| `events:fix_dst_occurrences` | Fixes occurrence times to match schedule without removing duplicates |
| `events:regenerate_all_occurrences` | Nuclear option - regenerates all future occurrences from scratch |
| `events:debug_dst` | Shows diagnostic info comparing DB times vs IceCube schedule |

**When to use:**
- After a DST transition if occurrences show wrong times
- If you see duplicate occurrences one hour apart
- After deploying timezone-related fixes

```bash
# Most common fix
rails events:full_dst_fix

# Just see what's wrong without changing anything
rails events:debug_dst
```

### Event Correction Tasks

| Task | Description |
|------|-------------|
| `events:fix_postponed_events` | Fixes events incorrectly postponed at event-level instead of occurrence-level |

**When to use:**
- If an event was postponed but the whole event shows as postponed instead of just one occurrence
- Migrating from old postponement behavior

```bash
rails events:fix_postponed_events
```

### Banner Image Tasks

| Task | Description |
|------|-------------|
| `banners:generate_spectra6` | Queue jobs to generate spectra6 versions of all banner images |
| `banners:generate_spectra6_sync` | Generate spectra6 versions synchronously (for debugging) |

**When to use:**
- After adding spectra6 support to regenerate existing banners
- If spectra6 versions are missing for some events

```bash
# Queue all for background processing
rails banners:generate_spectra6

# Process immediately (slower, shows errors)
rails banners:generate_spectra6_sync
```

### Instagram Integration Tasks

| Task | Description |
|------|-------------|
| `instagram:setup` | Set up Instagram credential from INSTAGRAM_ACCESS_TOKEN env var |
| `instagram:status` | Check Instagram token status (expiration, refresh capability) |
| `instagram:refresh` | Force refresh Instagram token |

**When to use:**
- Setting up Instagram integration for the first time
- Checking if token is expired or needs refresh
- Manually refreshing token if auto-refresh failed

```bash
# Initial setup (requires INSTAGRAM_ACCESS_TOKEN env var)
rails instagram:setup

# Check current status
rails instagram:status

# Force refresh (requires INSTAGRAM_APP_ID and INSTAGRAM_APP_SECRET)
rails instagram:refresh
```

### List All Available Tasks

```bash
# See all custom rake tasks
rails -T events
rails -T banners
rails -T instagram
```

## Occurrence Management

### Regenerate Occurrences for a Single Event

```ruby
event = Event.find_by(title: "Event Name")
# or
event = Event.find(123)

# Regenerate future occurrences (preserves slugs and statuses)
event.regenerate_future_occurrences!

# Generate occurrences (for events missing them)
event.generate_occurrences
```

### Regenerate All Occurrences (Background Job)

```ruby
# Trigger the daily regeneration job manually
RegenerateEventOccurrencesJob.perform_now
```

### View Upcoming Occurrences for an Event

```ruby
event = Event.find_by(title: "Event Name")
event.occurrences.upcoming.each do |occ|
  puts "#{occ.id}: #{occ.occurs_at.in_time_zone(Time.zone)} - #{occ.status}"
end
```

### Check Occurrence Times in Local Timezone

```ruby
event = Event.find_by(title: "Event Name")
event.occurrences.order(:occurs_at).each do |occ|
  local = occ.occurs_at.in_time_zone('America/Los_Angeles')
  puts "#{occ.id}: #{local.strftime('%Y-%m-%d %H:%M %Z')} (#{occ.status})"
end
```

## DST (Daylight Saving Time) Issues

### Debug DST Times

```bash
rails events:debug_dst
```

This shows the first 5 events with their:
- IceCube schedule start time
- Current occurrences in DB
- What IceCube would generate

### Fix DST-Related Issues

```bash
# Full fix: clean duplicates then fix times
rails events:full_dst_fix

# Just clean duplicate occurrences (same date, different times)
rails events:clean_duplicate_occurrences

# Just fix occurrence times (no duplicate removal)
rails events:fix_dst_occurrences

# Nuclear option: regenerate all future occurrences
rails events:regenerate_all_occurrences
```

### Manual DST Debugging

```ruby
event = Event.find_by(title: "Event Name")

# Check the IceCube schedule
schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
puts "Schedule start: #{schedule.start_time.in_time_zone(Time.zone)}"

# Compare DB vs IceCube
puts "\nDB Occurrences:"
event.occurrences.where('occurs_at > ?', Time.current).order(:occurs_at).limit(5).each do |occ|
  puts "  #{occ.occurs_at.in_time_zone(Time.zone)}"
end

puts "\nIceCube generates:"
schedule.occurrences_between(Time.current, 3.months.from_now).first(5).each do |d|
  puts "  #{d.in_time_zone(Time.zone)}"
end
```

## User Account Debugging

### Find a User

```ruby
user = User.find_by(email: "user@example.com")
# or
user = User.find(123)
```

### Check User Permissions

```ruby
user = User.find_by(email: "user@example.com")
puts "Role: #{user.role}"
puts "Admin: #{user.admin?}"
puts "Can create events: #{user.can_create_events}"
```

### List User's Events

```ruby
user = User.find_by(email: "user@example.com")

# Events created by user
user.events.each { |e| puts "#{e.id}: #{e.title}" }

# Events where user is a host
user.hosted_events.each { |e| puts "#{e.id}: #{e.title}" }
```

### Manually Set User as Admin

```ruby
user = User.find_by(email: "user@example.com")
user.update!(role: 'admin')
```

### Grant Event Creation Permission

```ruby
user = User.find_by(email: "user@example.com")
user.update!(can_create_events: true)
```

## Event Debugging

### Find Events

```ruby
# By title (partial match)
Event.where("title ILIKE ?", "%search term%")

# By status
Event.active
Event.cancelled
Event.permanently_cancelled

# By visibility
Event.public_events
Event.where(visibility: 'members')
Event.where(visibility: 'private')

# Draft events
Event.where(draft: true)
```

### Check Event Schedule

```ruby
event = Event.find(123)
puts "Recurrence type: #{event.recurrence_type}"
puts "Start time: #{event.start_time.in_time_zone(Time.zone)}"
puts "Max occurrences: #{event.max_occurrences}"

if event.recurrence_rule.present?
  schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
  puts "Schedule: #{schedule.to_s}"
end
```

### List Event Hosts

```ruby
event = Event.find(123)
event.hosts.each { |h| puts "#{h.id}: #{h.name} (#{h.email})" }
```

### Check Event Journal (Audit Log)

```ruby
event = Event.find(123)
event.event_journals.order(created_at: :desc).each do |j|
  puts "#{j.created_at}: #{j.action} by #{j.user&.name || 'System'}"
  puts "  Changes: #{j.changes_made}" if j.changes_made.present?
end
```

## Occurrence Debugging

### Find Occurrence by Slug

```ruby
occ = EventOccurrence.find_by(slug: "event-name-2026-03-15")
```

### Check Occurrence Status History

```ruby
occ = EventOccurrence.find(123)
puts "Status: #{occ.status}"
puts "Cancellation reason: #{occ.cancellation_reason}" if occ.cancellation_reason
puts "Postponed until: #{occ.postponed_until}" if occ.postponed_until
puts "Relocated to: #{occ.relocated_to}" if occ.relocated_to
```

### Manually Fix an Occurrence Time

```ruby
occ = EventOccurrence.find(123)
correct_time = Time.zone.local(2026, 3, 15, 19, 0, 0)
occ.update_column(:occurs_at, correct_time)
```

### Delete Duplicate Occurrences for an Event

```ruby
event = Event.find(123)

# Group by date
by_date = event.occurrences.group_by { |o| o.occurs_at.in_time_zone(Time.zone).to_date }

by_date.each do |date, occs|
  next unless occs.size > 1
  
  puts "Date #{date} has #{occs.size} occurrences:"
  occs.each { |o| puts "  #{o.id}: #{o.occurs_at.in_time_zone(Time.zone).strftime('%H:%M')} (#{o.status})" }
  
  # Keep the first one, delete the rest
  # occs[1..].each(&:destroy)
end
```

## Sidekiq / Background Jobs

### Check Sidekiq Status

```ruby
require 'sidekiq/api'

# Queue sizes
Sidekiq::Queue.all.each { |q| puts "#{q.name}: #{q.size}" }

# Scheduled jobs
Sidekiq::ScheduledSet.new.each { |job| puts "#{job.klass} at #{job.at}" }

# Failed jobs
Sidekiq::DeadSet.new.each { |job| puts "#{job.klass}: #{job.item['error_message']}" }
```

### Manually Run Scheduled Jobs

```ruby
# Regenerate occurrences
RegenerateEventOccurrencesJob.perform_now

# Post social media reminders
PostSocialRemindersJob.perform_now

# Send host email reminders  
SendHostEmailRemindersJob.perform_now
```

## Database Queries

### Events with Most Occurrences

```ruby
Event.joins(:occurrences)
     .group('events.id')
     .order('COUNT(event_occurrences.id) DESC')
     .limit(10)
     .pluck(:title, 'COUNT(event_occurrences.id)')
```

### Occurrences in the Next Week

```ruby
EventOccurrence.where(occurs_at: Time.current..1.week.from_now)
               .includes(:event)
               .order(:occurs_at)
               .each { |o| puts "#{o.occurs_at.in_time_zone(Time.zone)}: #{o.event.title}" }
```

### Events Without Upcoming Occurrences

```ruby
Event.active
     .where.not(recurrence_type: 'once')
     .left_joins(:occurrences)
     .where('event_occurrences.occurs_at IS NULL OR event_occurrences.occurs_at < ?', Time.current)
     .distinct
     .each { |e| puts "#{e.id}: #{e.title}" }
```

## Timezone Debugging

### Check Application Timezone

```ruby
puts "Rails timezone: #{Time.zone.name}"
puts "Time.current: #{Time.current}"
puts "Time.now: #{Time.now}"  # System time - may differ!
```

### Convert Times

```ruby
# UTC to local
utc_time = Time.utc(2026, 3, 15, 2, 0, 0)
local = utc_time.in_time_zone('America/Los_Angeles')
puts local  # 2026-03-14 19:00:00 -0700

# Local to UTC
local_time = Time.zone.local(2026, 3, 15, 19, 0, 0)
puts local_time.utc  # 2026-03-16 02:00:00 UTC
```

## Common Issues

### "Occurrences showing wrong time after DST"

Run `rails events:full_dst_fix` to clean duplicates and fix times.

### "Event not showing on calendar"

Check:
1. Is it a draft? `event.draft`
2. Is it permanently cancelled? `event.permanently_cancelled`
3. Does it have future occurrences? `event.occurrences.upcoming.count`
4. Is visibility correct? `event.visibility`

### "User can't create events"

Check:
1. User role: `user.role` (must be 'admin')
2. Or flag: `user.can_create_events` (must be true)

### "Duplicate occurrences appearing"

Run for specific event:
```ruby
event = Event.find(123)
event.regenerate_future_occurrences!
```

Or run for all events:
```bash
rails events:clean_duplicate_occurrences
```
