# Event Visibility Feature

## Overview

Events can now be marked with three visibility levels to control who can view them:

- 🌐 **Public** - Anyone can view (including non-authenticated users)
- 👥 **Members** - Only signed-in users can view
- 🔒 **Private** - Only the event owner and admins can view

## Access Control

### Public Events
- ✅ Visible to everyone (authenticated and unauthenticated)
- ✅ Shown on homepage
- ✅ Included in public event listings
- ✅ iCal feed accessible to anyone

### Members-Only Events
- ❌ Hidden from non-authenticated users
- ✅ Visible to any signed-in user
- ✅ Shown in event listings for members
- ✅ iCal feed requires authentication

### Private Events
- ❌ Hidden from non-authenticated users
- ❌ Hidden from other members
- ✅ Visible only to:
  - Event owner
  - Admin users
- ✅ Not shown in public listings

## User Experience

### Non-Authenticated Users (Visitors)
Can see:
- Public events only
- Can view event details
- Can access iCal feeds for public events

Cannot see:
- Members-only events
- Private events

### Authenticated Users (Members)
Can see:
- All public events
- All members-only events
- Their own private events
- Can create events with any visibility level

Cannot see:
- Other users' private events (unless admin)

### Admin Users
Can see:
- ALL events regardless of visibility
- Full access to all event details
- Can manage any event

## Setting Visibility

When creating or editing an event, choose from the dropdown:

1. **Public - Anyone can view**
   - Best for open events and workshops
   - Appears on public calendar

2. **Members Only - Signed in users can view**
   - For internal hackerspace events
   - Requires membership/login

3. **Private - Only you and admins can view**
   - For personal planning
   - Admin discussions
   - Not shown in public listings

## Database Schema

```ruby
# events table
t.string :visibility, default: 'public', null: false
```

**Valid values:** `public`, `members`, `private`

## Implementation

### Model Scopes

```ruby
Event.public_events    # All public events
Event.members_events   # All members-only events  
Event.private_events   # All private events
```

### Policy Enforcement

Visibility is enforced through **Pundit policies**:

```ruby
# app/policies/event_policy.rb
class EventPolicy::Scope
  def resolve
    if user.blank?
      # Not signed in - only show public events
      scope.public_events
    elsif user.admin?
      # Admins can see all events
      scope.all
    else
      # Regular users can see public, members, and their own private events
      scope.where(...)
    end
  end
end
```

### Controller Integration

```ruby
# Events are automatically filtered based on current user
@events = policy_scope(Event).includes(:user).order(:start_time)
```

## Visual Indicators

Events display visibility badges:

- 🌐 **Green badge** - Public
- 👥 **Blue badge** - Members Only
- 🔒 **Yellow badge** - Private

## Use Cases

### Public Events
- Workshops and classes
- Open hack nights
- Community events
- Public presentations

### Members Events
- Members meetings
- Internal workshops
- Social gatherings
- Equipment training

### Private Events
- Admin planning sessions
- Personal event planning
- Draft events (before publishing)
- Sensitive discussions

## Testing Visibility

1. **As a visitor** (not signed in):
   - Visit http://localhost:3000
   - Should only see public events

2. **As a regular user**:
   - Sign in as user1@example.com
   - Should see public + members events
   - Should NOT see other users' private events

3. **As an admin**:
   - Sign in as admin@example.com
   - Should see ALL events including private ones

## API Considerations

When exposing events via API:
- Always use `policy_scope(Event)` to respect visibility
- Include visibility in JSON responses
- Document visibility requirements in API docs

## Future Enhancements

Potential additions:
- Group/team-based visibility
- Time-based visibility (auto-publish)
- Visibility history/audit log
- Email notifications based on visibility
- Calendar feed filtering by visibility

