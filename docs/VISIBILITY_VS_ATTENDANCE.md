# Event Visibility vs. Attendance

Events now have TWO separate fields that control different aspects of event access:

## 1. Visibility (Who Can VIEW)

Controls **who can see the event** on the website.

| Level | Who Can See It | Access Control |
|-------|----------------|----------------|
| 🌐 **Public** | Everyone (including non-logged-in visitors) | ✅ Shows in public listings |
| 👥 **Members** | Only signed-in users | ❌ Hidden from visitors |
| 🔒 **Private** | Only owner and admins | ❌ Hidden from other members |

**Enforced by:** Pundit policies and database scopes

## 2. Open To (Who Can ATTEND)

Indicates **who is allowed to attend** the event. This is **informational only** - no access control.

| Level | Meaning | Example Use Case |
|-------|---------|------------------|
| 🚪 **Public** | Open to everyone | Public workshops, open house events |
| 👥 **Members** | Members only | Members meetings, internal workshops |
| ✉️ **Private** | By invitation only | Private gatherings, planning sessions |

**Enforced by:** None (display only)

---

## Why Two Fields?

These serve different purposes:

### Visibility = Access Control (Technical)
- **Purpose:** Security and privacy
- **Effect:** Directly controls what users can see
- **Enforced:** Yes, by the application
- **Example:** Private event is hidden from non-owners

### Open To = Attendance Policy (Social)
- **Purpose:** Event information and expectations
- **Effect:** Informs users about attendance rules
- **Enforced:** No, this is informational
- **Example:** Public event that's members-only attendance

---

## Common Combinations

### Example 1: Public Workshop
```
visibility: public   (anyone can see it)
open_to: public      (anyone can attend)
```
Perfect for community outreach events.

### Example 2: Members Meeting
```
visibility: members  (only members can see it)
open_to: members     (only members can attend)
```
Internal hackerspace business.

### Example 3: Published but Restricted Event
```
visibility: public   (everyone can see it)
open_to: members     (but only members can attend)
```
Use case: Promote a members-only event to encourage sign-ups.

### Example 4: Admin Planning
```
visibility: private  (only owner/admins can see)
open_to: private     (invitation only)
```
Confidential meetings.

---

## User Interface

### Event Form
Both fields appear side-by-side when creating/editing events:

```
[Visibility Dropdown]  [Open To Dropdown]
Who can see            Who can attend
```

### Event Display

**Event Cards:**
- Show both as badges
- Green/Blue/Yellow for visibility
- Gray badge for attendance

**Event Details:**
- Listed in the details section
- Clear labels and icons
- Explains the difference

---

## Implementation Notes

### Database
```ruby
# events table
t.string :visibility, default: 'public', null: false  # Access control
t.string :open_to, default: 'public', null: false     # Attendance info
```

### Model Validation
Both fields are validated:
```ruby
validates :visibility, inclusion: { in: %w[public members private] }
validates :open_to, inclusion: { in: %w[public members private] }
```

### Controller
Both are permitted parameters:
```ruby
params.require(:event).permit(..., :visibility, :open_to)
```

---

## Future Enhancements

Potential additions to `open_to`:
- RSVP system (track who's attending)
- Capacity limits
- Waitlist management
- Attendance confirmation
- Guest list for private events
- Member tier requirements (basic/premium/sponsor)

For now, `open_to` is **display-only** and doesn't enforce any restrictions.

