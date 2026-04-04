# Event Journal / Audit Log

## Overview

The Event Journal provides a complete audit trail of all changes made to events and their occurrences. Every modification is logged with:
- **Who** made the change (user)
- **What** changed (full text for descriptions, before/after values)
- **When** it happened (timestamp)
- **Context** (event or specific occurrence)

## What Gets Logged

### Event Changes
✅ Event creation  
✅ Title changes  
✅ Description changes  
✅ Duration changes  
✅ Start time changes  
✅ Visibility changes  
✅ Attendance policy changes  
✅ More info URL changes  
✅ Max occurrences changes  
✅ Recurrence rule changes  
✅ Adding co-hosts  
✅ Removing co-hosts  

### Occurrence Changes
✅ Occurrence status changes (postponed/cancelled/reactivated)  
✅ Custom description changes  
✅ Duration override changes  
✅ Postponement with new date  
✅ Cancellation with reason  
✅ Occurrence deletion  

## Who Can See the Journal

**Visible to:**
- Event hosts (all co-hosts)
- Admin users

**Hidden from:**
- Public users
- Non-host members
- Users who aren't involved with the event

## Journal Display

### Location
The journal appears at the bottom of the event detail page (`/events/:id`) for authorized users.

### Format
```
┌─────────────────────────────────────────────────────┐
│ 📖 Event Journal                                     │
├─────────────────────────────────────────────────────┤
│ ✏️ Updated event (title)                             │
│ 👤 admin@example.com · 🕐 5 minutes ago              │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Title:                                          │ │
│ │   ❌ Introduction to Arduino                    │ │
│ │   ✅ Advanced Arduino Programming               │ │
│ └─────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│ 👥 Added user1@example.com as co-host               │
│ 👤 admin@example.com · 🕐 10 minutes ago             │
└─────────────────────────────────────────────────────┘
```

### Features
- Timeline-style display (most recent first)
- Icons for different action types
- User attribution
- Relative time ("5 minutes ago")
- Absolute timestamp
- Before/after comparison for text changes
- Truncation of long text (200 chars)
- Limited to most recent 50 entries

## Database Schema

```ruby
create_table :event_journals do |t|
  t.references :event, null: false       # The event this log belongs to
  t.references :user, null: false        # Who made the change
  t.string :action, null: false          # What action was performed
  t.jsonb :change_data, default: {}      # Details of what changed
  t.integer :occurrence_id               # If it was an occurrence change
  t.timestamps
end
```

### Indexes
- `occurrence_id` - Quick lookup for occurrence changes
- `created_at` - Chronological sorting
- `[event_id, created_at]` - Event timeline queries

## Action Types

### Event Actions
- `created` - Event was created
- `updated` - Event details modified
- `host_added` - Co-host invited
- `host_removed` - Co-host removed

### Occurrence Actions
- `updated` - Occurrence details modified
- `cancelled` - Occurrence cancelled
- `postponed` - Occurrence postponed
- `reactivated` - Occurrence reactivated

## Change Data Structure

The `change_data` field stores a JSON object with details:

### Simple Changes
```json
{
  "visibility": { "from": "public", "to": "members" },
  "duration": { "from": 60, "to": 90 }
}
```

### Text Changes (Full Text Stored)
```json
{
  "title": {
    "from": "Introduction to Arduino",
    "to": "Advanced Arduino Programming"
  },
  "description": {
    "from": "Learn the basics...",
    "to": "Deep dive into advanced topics..."
  }
}
```

### Host Changes
```json
{
  "added_host": "user1@example.com"
}
```

### Status Changes
```json
{
  "status": "cancelled",
  "reason": "Instructor unavailable"
}
```

## Implementation

### Model Callbacks

**Event Model:**
```ruby
after_create :log_creation
after_update :log_update

# Requires setting:
event.current_user_for_journal = current_user
```

**EventOccurrence Model:**
```ruby
after_update :log_update

# Methods include user parameter:
occurrence.cancel!(reason, user)
occurrence.postpone!(until_date, reason, user)
occurrence.reactivate!(user)
```

### Controller Integration

Controllers set `current_user_for_journal` before saving:

```ruby
# EventsController
def update
  @event.current_user_for_journal = current_user
  @event.update(event_params)
end

# EventOccurrencesController  
def update
  @occurrence.current_user_for_journal = current_user
  @occurrence.update(occurrence_params)
end
```

### Manual Logging

For actions not captured by callbacks:

```ruby
# Log host addition
EventJournal.log_event_change(
  event,
  current_user,
  'host_added',
  { 'added_host' => user.email }
)

# Log occurrence cancellation
EventJournal.log_occurrence_change(
  occurrence,
  current_user,
  'cancelled',
  { 'reason' => 'Weather conditions' }
)
```

## Viewing the Journal

### In the UI

1. Navigate to an event you host or admin
2. Scroll to bottom of page
3. See "Event Journal" card
4. Entries shown in reverse chronological order

### In Rails Console

```ruby
# Get all journal entries for an event
event = Event.first
event.event_journals.recent_first

# Get journal entry details
journal = EventJournal.first
journal.summary  # Human-readable description
journal.formatted_changes  # Formatted change data
journal.user  # Who made the change
```

## Use Cases

### Accountability
Track who made changes and when:
- Useful for multi-host events
- Admin oversight
- Dispute resolution

### Debugging
Understand what happened:
- Why was this cancelled?
- Who changed the description?
- When was the time updated?

### History
Maintain institutional knowledge:
- Event evolution over time
- Decision rationale
- Communication trail

### Compliance
Audit trail for:
- Policy requirements
- Transparency
- Record keeping

## Example Journal Entries

### Event Created
```
Created event
By: admin@example.com
When: Nov 2, 2025 at 10:00 AM
Changes:
  - title: Weekly Hack Night
  - recurrence_type: weekly
  - visibility: public
```

### Title Changed
```
Updated event (title)
By: user1@example.com
When: Nov 2, 2025 at 2:30 PM
Changes:
  - Title:
      ❌ Weekly Hack Night
      ✅ Weekly Open Lab
```

### Occurrence Cancelled
```
Cancelled occurrence for November 16, 2025
By: admin@example.com
When: Nov 2, 2025 at 3:45 PM
Changes:
  - reason: Venue maintenance
```

### Co-Host Added
```
Added jane@example.com as co-host
By: admin@example.com
When: Nov 2, 2025 at 4:00 PM
```

## Privacy & Security

### Access Control
- Journal only visible to hosts and admins
- Uses same authorization as event editing
- Not visible in public views or API

### Data Retention
- Journals are kept indefinitely
- Deleted when event is deleted (cascade)
- 50 most recent shown in UI

### Sensitive Information
- Full text stored for audit purposes
- Passwords/tokens not logged (not event fields anyway)
- User emails shown (not considered sensitive in this context)

## Querying the Journal

```ruby
# All changes to an event
event.event_journals

# Recent changes
event.event_journals.recent_first.limit(10)

# Changes by specific user
event.event_journals.where(user: user)

# Occurrence-specific changes
event.event_journals.where.not(occurrence_id: nil)

# Specific action types
event.event_journals.where(action: 'cancelled')

# Changes in date range
event.event_journals.where(
  created_at: 1.month.ago..Time.now
)
```

## Future Enhancements

Potential additions:
- Export journal as CSV/PDF
- Email notifications for changes
- Slack/Discord integration
- Undo functionality
- Diff view for long text changes
- Filter by action type
- Search within journal
- Retention policies
- Journal for user changes
- API change logging

