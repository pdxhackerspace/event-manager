# Debugging Guide

This document contains helpful commands and procedures for debugging the EventManager application.

## Rails Console Access

```bash
# Production
docker exec -it eventmanager_app_1 rails console

# Development/Test
docker-compose -f docker-compose.test.yml run --rm app rails console
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
