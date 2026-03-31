# Multiple Hosts Feature

Events can now have multiple hosts/owners who can collaborate on managing the event.

## Overview

Each event has:
- **Creator** - The user who originally created the event (stored in `user_id`)
- **Hosts** - All co-hosts including the creator (many-to-many relationship)

## Key Concepts

### Creator vs. Hosts

**Creator (Owner):**
- The user who created the event
- Cannot be removed as a host if they're the only one
- Only the creator can delete the event
- Automatically becomes the first host

**Hosts:**
- Multiple users who can manage the event
- All hosts can edit, postpone, and cancel events
- Can invite additional co-hosts
- Can be removed by other hosts or admins (except creator)

## Permissions

### What Hosts Can Do:
✅ View the event (even if private)  
✅ Edit event details  
✅ Postpone the event  
✅ Cancel the event  
✅ Invite additional co-hosts  
✅ Remove other co-hosts (except creator)  

### What Only Creator Can Do:
⭐ Delete the event permanently

### What Admins Can Do:
👑 Everything (view, edit, delete, manage hosts for any event)

## User Interface

### Event Show Page

**Hosts Section:**
```
Hosts:
  • Jane Smith                    [×]
  • Admin User (creator)
```

- Lists all hosts
- Shows who is the creator
- Remove button (×) for non-creator hosts
- Only visible to hosts and admins

**Invite Co-Host Card:**
```
┌─────────────────────────────────┐
│ Invite Co-Host                  │
│                                 │
│ [Dropdown: Select User...]      │
│                                 │
│ [Add as Co-Host Button]         │
└─────────────────────────────────┘
```

- Dropdown shows users not already hosts
- Only visible to existing hosts and admins
- Simple one-click invitation

### Events Index

Shows all hosts when multiple:
```
👤 Admin User, Jane Smith
```

Shows single host normally:
```
👤 John Doe
```

## Database Schema

### event_hosts Table (Join Table)
```ruby
t.references :event, null: false, foreign_key: true
t.references :user, null: false, foreign_key: true
t.timestamps

# Unique index to prevent duplicate host entries
add_index [:event_id, :user_id], unique: true
```

### events Table
```ruby
t.references :user  # Creator/owner (not changed)
# hosts accessed through event_hosts join table
```

## Model Methods

### Event Model

```ruby
# Check if user is a host
event.hosted_by?(user)  # => true/false

# Add a co-host
event.add_host(user)

# Remove a co-host
event.remove_host(user)

# Get creator
event.creator  # => User object

# Get all hosts
event.hosts  # => ActiveRecord Collection
```

### Automatic Behavior

When an event is created:
1. Creator is automatically added as the first host
2. `after_create :add_creator_as_host` callback handles this

## Authorization Flow

### Viewing Events
- Public events: Anyone
- Members events: Signed-in users  
- Private events: Hosts + admins only

### Editing Events
- Hosts can edit
- Admins can edit
- Non-hosts cannot edit

### Deleting Events
- Only creator can delete
- Admins can delete any event

### Managing Hosts
- Existing hosts can add/remove co-hosts
- Admins can add/remove any hosts
- Creator cannot be removed if they're the only host

## API Endpoints

```
POST   /events/:event_id/event_hosts       # Add a co-host
DELETE /event_hosts/:id                    # Remove a co-host
```

Parameters:
- `user_id` - ID of user to add as host

## Use Cases

### Example 1: Workshop with Multiple Instructors
```
Event: Welding Basics
Creator: user1@example.com
Hosts: user1@example.com, user2@example.com
```
Both instructors can update the event details, postpone if needed, etc.

### Example 2: Recurring Event with Rotating Hosts
```
Event: Weekly Hack Night
Creator: admin@example.com
Hosts: admin@example.com, user1@example.com, user2@example.com
```
Multiple people share responsibility for the weekly event.

### Example 3: Large Event with Planning Committee
```
Event: Annual Hackathon
Creator: admin@example.com
Hosts: admin@example.com, user1@example.com, user2@example.com, user3@example.com
```
Planning committee members can all manage the event.

## Adding Co-Hosts

### As Event Host:
1. View your event
2. Scroll to "Invite Co-Host" card
3. Select user from dropdown
4. Click "Add as Co-Host"

### As Admin:
1. View any event
2. Use same invite form
3. Can add any user as co-host

## Removing Co-Hosts

### As Event Host:
1. View the event
2. Find host in "Hosts" section
3. Click [×] button next to their name
4. Confirm removal

**Note:** Creator cannot be removed if they're the only host.

### As Admin:
- Can remove any host except creator when they're the only one

## Backend Implementation

### Models

**Event:**
```ruby
has_many :event_hosts, dependent: :destroy
has_many :hosts, through: :event_hosts, source: :user
belongs_to :user  # creator
```

**EventHost:**
```ruby
belongs_to :event
belongs_to :user
validates :user_id, uniqueness: { scope: :event_id }
```

**User:**
```ruby
has_many :events  # created events
has_many :event_hosts
has_many :hosted_events, through: :event_hosts, source: :event
```

### Controllers

**EventHostsController:**
- Handles adding and removing hosts
- Requires authentication
- Checks authorization (must be existing host or admin)

**EventsController:**
- Updated to eager load `:hosts` for performance
- Authorization uses `hosted_by?` instead of owner check

### Policies

**EventPolicy:**
```ruby
def update?
  user.admin? || record.hosted_by?(user)
end

def destroy?
  user.admin? || user == record.user  # creator only
end
```

## Testing

```bash
# In Rails console
docker compose exec web rails console

# Create event
event = Event.first

# Add co-host
user2 = User.find_by(email: 'user2@example.com')
event.add_host(user2)

# Check hosts
event.hosts  # All hosts
event.hosts.count  # Number of hosts

# Check if someone is a host
event.hosted_by?(user2)  # true

# Remove host
event.remove_host(user2)
```

## Future Enhancements

Potential additions:
- Host roles (primary host, co-host, assistant)
- Email invitations for external hosts
- Host permissions (some can edit, some can only view)
- Host activity log
- Notification to user when added as host
- Host acceptance/rejection workflow
- Host roster on event page with contact info

