# Event Occurrences System

## Overview

The EventManager uses a two-level system to handle recurring and one-time events:

1. **Event** - The template/series definition with recurrence rules
2. **Occurrence** - Individual happenings of an event

This allows you to cancel or postpone specific instances without affecting the entire series.

## Terminology

**Event** = The series or template  
**Occurrence** = A specific happening/instance of the event

Example:
- Event: "Weekly Hack Night" (recurring)
- Occurrences: Nov 9, Nov 16, Nov 23, Nov 30, Dec 7...

## Key Concepts

### Events Define the Template

Events contain:
- Title, description, hosts
- Recurrence rules (weekly, monthly, etc.)
- `max_occurrences` - How many future occurrences to generate/display
- Visibility and attendance settings
- Start time and duration (defaults for occurrences)

### Occurrences Are the Actual Happenings

Each occurrence has:
- `occurs_at` - Specific date/time
- `status` - active, postponed, or cancelled
- `custom_description` - Override event description (optional)
- `duration_override` - Override event duration (optional)
- `cancellation_reason` - Why postponed/cancelled (optional)
- `postponed_until` - New date if postponed (optional)

## How It Works

### Automatic Generation

**When you create an event:**
1. Event is saved with recurrence rules
2. Occurrences are automatically generated
3. Number generated = `max_occurrences` setting (default: 5)

**For one-time events:**
- Creates 1 occurrence at the event's start_time

**For recurring events:**
- Generates up to `max_occurrences` future occurrences
- Uses IceCube gem to calculate dates from recurrence rules

### Managing Individual Occurrences

**Cancel one occurrence:**
```
Event: Weekly Meetup
Nov 9  ✅ Active
Nov 16 ❌ Cancelled (special workshop that night)
Nov 23 ✅ Active
Nov 30 ✅ Active
```

The series continues - only Nov 16 is affected!

**Postpone one occurrence:**
```
Event: Monthly Meeting
Dec 5  ⏰ Postponed to Dec 12 (venue conflict)
Jan 2  ✅ Active
Feb 6  ✅ Active
```

### Customizing Individual Occurrences

Each occurrence can override:
- **Description** - Different topic/agenda for this instance
- **Duration** - Shorter or longer than usual

Example:
```
Event: Arduino Workshop (usually 2 hours)

Nov 15 occurrence:
  Description: "Intro to Arduino - Basics only"
  Duration: 90 minutes (custom)

Nov 22 occurrence:
  Description: (uses event description)
  Duration: 120 minutes (default)
```

## User Interface

### Events View (`/events`)
Shows event series with:
- Event title and description
- Recurrence pattern
- Link to view upcoming occurrences

### Calendar View (`/calendar`)
Shows ALL upcoming occurrences:
- Grouped by month
- Large day numbers for easy scanning
- Shows event title, time, hosts
- Status indicators (cancelled/postponed)
- Directly links to occurrence details

### Event Page (`/events/:id`)
Shows:
- Event details and settings
- List of upcoming occurrences (up to `max_occurrences`)
- Each occurrence shows status
- Link to view/manage individual occurrences

### Occurrence Page (`/occurrences/:id`)
Shows:
- Specific date/time
- Description (custom or inherited)
- Duration (override or default)
- Status and cancellation reason
- Links back to event series
- Manage buttons (postpone, cancel, delete for hosts/admins)

## Managing Occurrences

### As a Host

**View an occurrence:**
1. Go to event page
2. Click occurrence in list
3. Or use calendar view

**Edit an occurrence:**
1. View the occurrence
2. Click "Edit Details"
3. Add custom description/duration
4. Changes only affect this occurrence

**Cancel an occurrence:**
1. View the occurrence
2. Click "Cancel This Occurrence"
3. Enter optional reason
4. Only this occurrence is cancelled

**Delete an occurrence:**
1. View the occurrence
2. Click "Delete This Occurrence"
3. Confirm - occurrence is removed
4. Event series continues

### As an Admin

Admins can manage ANY occurrence of ANY event.

## Database Schema

### events table
```ruby
t.string :title
t.text :description
t.datetime :start_time  # Template start time
t.integer :duration  # Default duration
t.text :recurrence_rule  # IceCube YAML
t.string :recurrence_type
t.integer :max_occurrences, default: 5  # How many to generate
# ... other fields
```

### event_occurrences table
```ruby
t.references :event
t.datetime :occurs_at  # Specific date/time
t.string :status, default: 'active'
t.text :custom_description  # Override event description
t.integer :duration_override  # Override event duration
t.datetime :postponed_until
t.text :cancellation_reason
```

## Model Methods

### Event Methods

```ruby
# Generate future occurrences
event.generate_occurrences(limit)

# Get upcoming active occurrences
event.upcoming_occurrences(limit)

# Regenerate all future occurrences
event.regenerate_future_occurrences!

# Access occurrences
event.occurrences  # All occurrences
event.event_occurrences  # Same
```

### EventOccurrence Methods

```ruby
# Get effective description
occurrence.description  # Returns custom or event description

# Get effective duration
occurrence.duration  # Returns override or event duration

# Status management
occurrence.postpone!(until_date, reason)
occurrence.cancel!(reason)
occurrence.reactivate!

# Display name
occurrence.name  # "Event Title - Nov 15, 2025"
```

## Setting max_occurrences

When creating/editing an event:

**Form field:** "Show Next"
- Minimum: 1
- Maximum: 20
- Default: 5

**Effect:**
- Controls how many future occurrences are generated
- If you change from 5 to 10, 5 more occurrences are created
- If you change from 10 to 5, no occurrences are deleted (manual management)

## Common Workflows

### Weekly Event with Occasional Cancellations

```
1. Create event: "Tuesday Game Night" (weekly, max: 8)
2. System generates next 8 Tuesday occurrences
3. Thanksgiving week: Cancel Nov 26 occurrence
4. Other occurrences continue normally
```

### Monthly Event with Custom Topics

```
1. Create event: "First Friday Talks" (monthly, max: 6)
2. System generates next 6 first-Friday occurrences
3. Edit Nov occurrence: custom_description = "Topic: 3D Printing"
4. Edit Dec occurrence: custom_description = "Topic: Arduino Projects"
5. Each month shows different topic
```

### One-Time Event

```
1. Create event: "Hackathon 2025" (once)
2. System creates 1 occurrence
3. If postponed: Update the occurrence, not the event
```

## Calendar View Features

### Grouping
- Occurrences grouped by month
- Clear month headers
- Easy to scan upcoming events

### Display
- Large day number for quick reference
- Event title (links to event series)
- Time and duration
- Host information
- Status badges
- Quick links to both event and occurrence

### Filtering
- Respects event visibility settings
- Public users see public event occurrences only
- Members see member + public occurrences
- Admins see all occurrences

## API Endpoints

```
GET    /events/:id                        # Event series
GET    /occurrences/:id                   # Specific occurrence
PATCH  /occurrences/:id                   # Edit occurrence
DELETE /occurrences/:id                   # Delete occurrence
POST   /occurrences/:id/postpone          # Postpone occurrence
POST   /occurrences/:id/cancel            # Cancel occurrence
POST   /occurrences/:id/reactivate        # Reactivate occurrence
GET    /calendar                          # Calendar view
```

## Automatic Regeneration

Occurrences are regenerated when:
- Event's `recurrence_rule` changes
- Event's `start_time` changes
- Event's `max_occurrences` changes

**Behavior:**
- Deletes future unmodified active occurrences
- Regenerates based on new settings
- Keeps modified occurrences (postponed/cancelled)

## Best Practices

### For Event Hosts

**Setting max_occurrences:**
- Weekly events: 4-8 weeks ahead
- Monthly events: 6-12 months ahead
- Consider your planning horizon

**Cancelling vs. Deleting:**
- **Cancel** if you want people to know it was scheduled
- **Delete** if it was a mistake/duplicate

**Custom descriptions:**
- Use for topics, guests, special notes
- Helps attendees know what to expect

### For Admins

**Bulk operations:**
- Edit event series for changes affecting all
- Edit occurrences for one-time adjustments

**Monitoring:**
- Use calendar view to see overall schedule
- Check for conflicts or gaps

## Examples

### Example 1: Weekly Event
```ruby
event = Event.create!(
  title: "Arduino Workshop",
  recurrence_type: 'weekly',
  max_occurrences: 6
)
# Creates 6 weekly occurrences automatically
```

### Example 2: Cancel One Meeting
```ruby
occurrence = event.occurrences.where(
  occurs_at: Date.new(2025, 11, 23)
).first

occurrence.cancel!("Thanksgiving week - no meeting")
# Other weeks continue normally
```

### Example 3: Custom Description
```ruby
occurrence.update(
  custom_description: "Special topic: Building a Weather Station"
)
# This occurrence now has custom description
# Others use event description
```

## Troubleshooting

**Q: I changed max_occurrences but don't see more occurrences**
A: The system generates future occurrences. If all generated dates are in the past, none will show. Check event's start_time.

**Q: Can I delete all occurrences at once?**
A: Delete the event - this cascades to all occurrences.

**Q: What happens if I delete an occurrence?**
A: Just that occurrence is removed. The event series continues.

**Q: Can I manually create occurrences?**
A: Yes, but it's better to adjust max_occurrences and let the system generate them.

## Future Enhancements

Potential additions:
- Attendance tracking per occurrence
- RSVP system for occurrences
- Occurrence templates/presets
- Bulk occurrence editing
- Occurrence notifications
- Waitlist per occurrence
- Capacity limits per occurrence

