# Plan: Capacity Limits, RSVPs, and Wait Lists

Status: draft for review. Target version: **0.25.0** (feature release).
Branch: `feature/rrsvp`

## Goals

- Events can optionally take RSVPs, with or without a capacity limit.
- When a capacity-limited occurrence is full, new RSVPs go to a wait list.
- Hosts and admins can see the RSVP and wait lists, and can cancel people on them.
- Each RSVP gets a confirmation email containing a private management link that works until the occurrence ends.
- Attendees get reminder emails before the event.
- For capacity-limited events, reminders nag people to release their spot if they can't make it.
- When a spot opens, people on the wait list are emailed and offered the spot.

## Key design decisions

### RSVPs attach to occurrences, not events

Events are recurring, and each date is an `EventOccurrence`. A person RSVPs to a specific occurrence. Capacity settings live on the `Event`, and an occurrence can override them, following the same pattern as `duration` / `duration_override`.

### Who can RSVP

| `open_to`  | Who can RSVP                                                          |
|------------|-----------------------------------------------------------------------|
| `public`   | Logged-in users (one click), or guests with name + email              |
| `members`  | Logged-in users only                                                  |
| `private`  | Logged-in users only. Hosts can also add people manually              |

Guest RSVPs to a capacity-limited event start as `pending` and only take a spot after the guest clicks the link in the confirmation email. That stops typos and bots from filling the event.

### Management link

Each RSVP has a random `manage_token` (`has_secure_token`, unique index). The link is `/rsvps/:token`. It is valid until the occurrence ends, using the same end-time calculation as `EventOccurrence::END_TIME_SQL`. After that, the page says the event is over. A token in the database is used instead of `generates_token_for` because the expiry depends on the occurrence time, and that time can change through postponement or edits. Logged-in users can also manage their RSVPs from the dashboard.

### Seat allocation and concurrency

All RSVP create, cancel, and promote operations run inside `occurrence.with_lock` (a row lock on the occurrence), so two people can't take the last seat at the same time. A spot counts as taken when the RSVP status is `confirmed`, or when it is `offered` and the offer hasn't expired yet.

### Wait list offers

When a spot opens (a cancellation, an expired offer, or an increased capacity), the next person on the wait list gets an **offer** with a deadline. If they accept, they're confirmed. If the offer expires, the spot is offered to the next person.

- The offer window scales with how close the event is. The default is 24 hours, but it is never more than half the time remaining before the event, with a minimum of 1 hour.
- Inside a configurable cutoff (default 4 hours before start), there are no individual offers. Every waitlisted person is emailed that a spot is open, and the first one to claim it gets it.
- Hosts can manually promote someone from the wait list, skipping the offer step.

## Data model

### Migration: `events`

- `rsvp_enabled` boolean, default false
- `capacity` integer, nullable (null = unlimited)
- `waitlist_enabled` boolean, default true (only meaningful when `capacity` is set)
- `max_guests_per_rsvp` integer, default 0 (the number of "+1"s allowed per RSVP)
- `rsvp_closes_minutes_before` integer, default 0

### Migration: `event_occurrences`

- `capacity_override` integer, nullable
- `rsvp_disabled` boolean, default false (turns RSVPs off for one date)

### Migration: `site_configs`

- `rsvps_enabled` boolean, default true (site-wide kill switch)
- `rsvp_offer_hours` integer, default 24
- `rsvp_last_call_hours` integer, default 4

### New table: `rsvps`

| Column                | Notes                                                                 |
|-----------------------|-----------------------------------------------------------------------|
| `event_occurrence_id` | FK, not null                                                          |
| `user_id`             | FK, nullable (null for guests)                                        |
| `name`, `email`       | Copied from the user when logged in; required for guests              |
| `guest_count`         | integer, default 0 (counts against capacity)                          |
| `status`              | `pending`, `confirmed`, `waitlisted`, `offered`, `cancelled` (check constraint) |
| `waitlisted_at`       | Sets wait list order                                                  |
| `offered_at`, `offer_expires_at` |                                                            |
| `confirmed_at`        |                                                                       |
| `cancelled_at`, `cancelled_by_id`, `cancellation_reason`, `cancelled_via` | `cancelled_via` is `self`, `host`, `admin`, `offer_expired`, or `occurrence_cancelled` |
| `manage_token`        | unique index                                                          |
| `reminder_7d_sent_at`, `reminder_1d_sent_at`, `reminder_day_of_sent_at`, `release_nag_sent_at` | Make the reminder job idempotent |
| `attended`            | boolean, nullable (for a later check-in feature)                      |

Indexes:

- Unique on `(event_occurrence_id, lower(email))` where `status <> 'cancelled'`, so the same person can't RSVP twice.
- `(event_occurrence_id, status, waitlisted_at)` for wait list ordering.

### Models and services

- `Rsvp` model with scopes (`holding_spot`, `waitlisted`, `active`) and status predicates.
- `EventOccurrence#effective_capacity`, `#spots_taken`, `#spots_remaining`, `#full?`, `#rsvp_open?`.
- `RsvpService` in `app/services/` does all the state changes inside the lock: `create`, `confirm_pending`, `cancel`, `accept_offer`, `promote`, and `fill_open_spots`. Controllers and jobs call this service and never update RSVP status directly.
- Journal entries (`EventJournal`) when hosts or admins cancel, promote, or add people.

## Emails (`RsvpMailer`)

All emails follow the existing email test mode (`SiteConfig#email_test_mode_*`). That logic is currently in `HostReminderNotificationJob#determine_recipient_email`, so it moves into a shared concern first.

| Email                  | When                                                       | Contents                                         |
|------------------------|------------------------------------------------------------|--------------------------------------------------|
| `confirm_email`        | Guest RSVP to a capacity-limited event                     | Link to confirm                                  |
| `confirmed`            | RSVP confirmed                                             | Details, manage link, `.ics` attachment          |
| `waitlisted`           | Added to the wait list                                     | Position, manage link                            |
| `spot_offered`         | Offered a spot from the wait list                          | Accept / decline buttons, deadline               |
| `last_call`            | Spot open inside the last-call window                      | "First to claim it gets it"                      |
| `offer_expired`        | Offer lapsed                                               | Back on the wait list or removed (decision below)|
| `reminder`             | 7 days, 1 day, and the morning of                          | Details, manage link                             |
| `release_nag`          | Capacity-limited and the event is full or has a wait list | "Can't make it? Release your spot" one-click link |
| `cancelled_by_host`    | Host or admin cancelled the RSVP                           | Optional reason                                  |
| `occurrence_changed`   | Occurrence cancelled, relocated, or its time changed       | New details, or the cancellation notice          |

The `release_nag` email is sent about 2 days before the event and combined with the 1-day reminder, so people don't get two emails on the same day.

## Jobs

- `RsvpReminderJob`, run hourly by the scheduler. It finds RSVPs where the reminder hasn't been sent and the reminder time has passed, sends the email, and sets the `*_sent_at` column. Running hourly instead of daily means reminders go out a consistent amount of time before each event.
- `RsvpOfferExpiryJob`, run every 15 minutes. It expires lapsed offers and calls `RsvpService#fill_open_spots`.
- `RsvpService` calls `fill_open_spots` immediately after any cancellation or capacity increase.

## Occurrence lifecycle integration

- **Cancelled**: email everyone on the RSVP list and wait list, and mark their RSVPs `cancelled` with `cancelled_via: occurrence_cancelled`. Reactivating the occurrence does not restore them. The email says so.
- **Postponed**: `postpone!` creates a new occurrence. Move the RSVPs to the new occurrence and email everyone the new date, so their links keep working. Re-check capacity if the new occurrence has a different override.
- **Relocated** or **time edited**: email everyone with the change.
- **Capacity reduced** below the number of confirmed spots: nobody is bumped. New RSVPs go to the wait list until the count drops. Hosts see a warning.
- **Capacity increased**: run `fill_open_spots`.
- **Event or occurrence soft-deleted**: treat it the same as cancelled.

## UI

### Public occurrence / event page

- RSVP button that shows the count, for example "RSVP (8 of 20 spots left)", or "Full: join wait list".
- If the viewer has already RSVP'd: their status, wait list position, and a cancel button.
- Guest form: name, email, guest count, and a honeypot field. Rate limited with Rails 8 `rate_limit`.
- Attendee names are never shown publicly. Counts are only shown when capacity is set.

### Management page (`/rsvps/:token`)

- Status, event details, cancel button, accept/decline for an open offer, and a toggle to opt out of reminders.

### Host / admin view (on the occurrence page, plus `/occurrences/:slug/rsvps`)

- Tabs for confirmed, wait list (in order), offered (with deadline), pending, and cancelled.
- Actions: cancel (with an optional reason that is emailed), promote from the wait list, resend confirmation, and add a person manually.
- CSV export.
- Authorization reuses `Event#hosted_by?` (hosts and admins).

### Event form

- An "RSVPs" section with the enable toggle, capacity, wait list toggle, guests per RSVP, and the RSVP cutoff. On the occurrence edit form, a capacity override and a toggle to turn RSVPs off for that date.

### Dashboard

- "My RSVPs" list for logged-in users.
- Hosts see RSVP counts for their upcoming occurrences.

## Phases (each one commits separately with tests)

1. **Schema and models**: migrations, `Rsvp` model, capacity methods on the occurrence, `RsvpService` with locking, and model/service tests (including concurrency on the last seat).
2. **RSVP flow**: public RSVP and cancel for logged-in users and guests, the management page, the confirmation and wait list emails, and the `.ics` attachment.
3. **Host / admin lists**: the list view, cancel and promote actions, CSV export, and journal entries.
4. **Wait list offers**: the offer, accept, and expiry cycle, the last-call broadcast, and the expiry job.
5. **Reminders and the release nag**: the hourly job, reminder opt-out, and idempotency tests.
6. **Lifecycle integration**: cancellation, postponement, relocation, time change, and capacity changes.
7. **Polish**: dashboard sections, event form UI, site config settings, the docs update, a CHANGELOG entry, and the version bump to 0.25.0.

## Open questions

1. **Guest RSVPs**: should public events accept RSVPs from people without an Authentik account, or should RSVPs require logging in?
2. **Wait list offers**: should offers go to one person at a time with a deadline (as planned), or should everyone on the wait list be emailed and the first to claim the spot get it?
3. **Expired offers**: if someone ignores an offer, do they go back to the end of the wait list, or are they removed?
4. **Recurring events**: is a "RSVP to every upcoming date" option needed, or is one occurrence at a time enough for now?
5. **Plus-ones**: should an RSVP be able to include extra guests that count against capacity?
6. **Host notifications**: should hosts get an email for each new RSVP or cancellation, a daily digest, or nothing?
7. **No-shows**: is a check-in / attendance feature wanted later, which would track repeat no-shows for capacity-limited events?
8. **Data retention**: should guest names and emails be purged some number of days after the event?
