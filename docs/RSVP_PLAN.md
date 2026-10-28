# Plan: Capacity Limits, RSVPs, and Wait Lists

Status: approved for implementation. Target version: **0.25.0** (feature release).
Branch: `feature/rrsvp`

## Goals

- Events can optionally take RSVPs, with or without a capacity limit.
- When a capacity-limited occurrence is full, new RSVPs go to a wait list.
- Hosts and admins can see the RSVP and wait lists, and can cancel people on them.
- Each RSVP gets a confirmation email containing a private management link that works until the occurrence ends.
- Attendees get reminder emails before the event.
- For capacity-limited events, reminders nag people to release their spot if they can't make it.
- When a spot opens, people on the wait list are emailed and offered the spot.
- Hosts can check people in at the event, and no-shows are tracked.

## Out of scope

- RSVPing to every date of a recurring event at once. Each RSVP is for one occurrence.
- Plus-ones. Every RSVP is exactly one person.
- Digest emails for hosts.

## Key design decisions

### RSVPs attach to occurrences, not events

Events are recurring, and each date is an `EventOccurrence`. A person RSVPs to a specific occurrence. Capacity settings live on the `Event`, and an occurrence can override them, following the same pattern as `duration` / `duration_override`.

### Who can RSVP

| `open_to`  | Who can RSVP                                                          |
|------------|-----------------------------------------------------------------------|
| `public`   | Logged-in users (one click), or guests with name + email              |
| `members`  | Logged-in users only                                                  |
| `private`  | Logged-in users only. Hosts can also add people manually              |

- **Guests with an account must log in.** If the email on a guest RSVP matches an existing `User` (compared case-insensitively), the RSVP is not created. The guest is asked to log in, and is returned to the RSVP after logging in. The response doesn't reveal whether the account exists. It tells the guest to log in if they have an account, and otherwise sends the confirmation email to that address. If the email does match an account, that message tells them to log in instead.
- **Guests confirm their email.** Guest RSVPs start as `pending` and only hold a spot (or a wait list place) after the guest clicks the link in the confirmation email. That stops typos and bots from filling the event. Pending RSVPs that aren't confirmed within 24 hours, or by the start of the event if that's sooner, are deleted.
- When a user logs in, any guest RSVPs made with their email are linked to their account.

### Management link

Each RSVP has a random `manage_token` (`has_secure_token`, unique index). The link is `/rsvps/:token`. It is valid until the occurrence ends, using the same end-time calculation as `EventOccurrence::END_TIME_SQL`. After that, the page says the event is over. A token in the database is used instead of `generates_token_for` because the expiry depends on the occurrence time, and that time can change through postponement or edits. Logged-in users can also manage their RSVPs from the dashboard.

### Seat allocation and concurrency

All RSVP create, cancel, accept, and promote operations run inside `occurrence.with_lock` (a row lock on the occurrence), so two people can't take the last seat at the same time. A spot counts as taken when the RSVP status is `confirmed`, or when it has an unexpired held offer (sequential mode only).

### Wait list modes (host's choice per event)

`events.waitlist_mode` is either `first_come` (the default) or `sequential`.

**First come, first served (`first_come`)**
- When a spot opens, every waitlisted person who hasn't already been told about the open spot gets a "spot open" email with a claim link.
- The first person to claim the spot gets it. Anyone who clicks after it's taken sees "it was taken" and stays on the wait list.
- No spot is held for anyone.

**Sequential offers (`sequential`)**
- When a spot opens, it is held for the next person on the wait list who doesn't have an offer, with a deadline. The default deadline is 24 hours. It is never more than half the time remaining before the event, with a minimum of 1 hour.
- When the deadline passes, the hold is released and the spot is offered to the next person.
- Inside the last-call window (default 4 hours before the start), there are no more holds. The mode switches to first come, first served for everyone left on the wait list.

**Both modes**
- **Ignored offers don't remove anyone.** A person stays on the wait list until they accept a spot, cancel, or a host removes them. After their hold expires, their claim link still works if a spot is open and not held for someone else.
- **One offer reminder.** Each person gets one reminder about an offer they haven't acted on, sent halfway to the deadline in sequential mode, or 12 hours after the "spot open" email in first come mode. It is only sent if a spot is still open, and the RSVP records the time so it is never sent twice.
- Hosts can promote someone from the wait list manually, skipping offers.
- Changing the mode while offers are out releases the existing holds, and the new mode applies from then on.

### Privacy

- Hosts see attendee **names only**. They never see emails (for guests or account users), including in the CSV export.
- Admins see names and emails.
- Attendee names are never shown publicly. Counts are only shown when capacity is set.
- Guest data retention: a daily job anonymizes guest RSVPs (it clears the name and email and sets `anonymized_at`) after `site_configs.rsvp_guest_retention_days`, which defaults to 30 days after the occurrence. Attendance counts are kept. RSVPs belonging to account users aren't anonymized, because no-show history depends on them.

### Host notifications

`event_hosts.notify_on_rsvp` is a boolean, off by default. Each host sets it for themselves on each event. When it's on, the host gets one email for each new confirmed RSVP, cancellation, and wait list join. The email shows names only.

### Check-in and no-shows

- During the event (from 1 hour before the start until 12 hours after the end), hosts get a check-in view with a checkbox for each confirmed RSVP. Checking someone in sets `attended = true`.
- Once the check-in window closes, a job marks confirmed RSVPs that weren't checked in as `attended = false`. This only happens for occurrences where at least one person was checked in, so occurrences where nobody used check-in aren't counted as all no-shows.
- No-show history is tracked for account users only. Hosts see a count of recent no-shows (the last 90 days) next to each name on capacity-limited events. For now this is information only, and nobody is blocked from RSVPing.

## Data model

### Migration: `events`

- `rsvp_enabled` boolean, default false
- `capacity` integer, nullable (null = unlimited)
- `waitlist_enabled` boolean, default true (only meaningful when `capacity` is set)
- `waitlist_mode` string, default `first_come`, with a check constraint (`first_come`, `sequential`)
- `rsvp_closes_minutes_before` integer, default 0

### Migration: `event_occurrences`

- `capacity_override` integer, nullable
- `rsvp_disabled` boolean, default false (turns RSVPs off for one date)
- `checkin_finalized_at` datetime

### Migration: `event_hosts`

- `notify_on_rsvp` boolean, default false

### Migration: `site_configs`

- `rsvps_enabled` boolean, default true (site-wide kill switch)
- `rsvp_offer_hours` integer, default 24
- `rsvp_last_call_hours` integer, default 4
- `rsvp_guest_retention_days` integer, default 30

### New table: `rsvps`

| Column                | Notes                                                                 |
|-----------------------|-----------------------------------------------------------------------|
| `event_occurrence_id` | FK, not null                                                          |
| `user_id`             | FK, nullable (null for guests)                                        |
| `name`, `email`       | Copied from the user when logged in; required for guests; nullable once anonymized |
| `status`              | `pending`, `confirmed`, `waitlisted`, `cancelled` (check constraint)  |
| `waitlisted_at`       | Sets wait list order                                                  |
| `offer_held_until`    | Set while a sequential-mode hold is active                            |
| `last_offered_at`     | When the latest "spot open" or offer email was sent                   |
| `offer_reminder_sent_at` |                                                                    |
| `confirmed_at`        |                                                                       |
| `cancelled_at`, `cancelled_by_id`, `cancellation_reason`, `cancelled_via` | `cancelled_via` is `self`, `host`, `admin`, or `occurrence_cancelled` |
| `manage_token`        | unique index                                                          |
| `reminders_opted_out` | boolean, default false                                                |
| `reminder_7d_sent_at`, `reminder_1d_sent_at`, `reminder_day_of_sent_at`, `release_nag_sent_at` | Make the reminder job idempotent |
| `attended`            | boolean, nullable                                                     |
| `checked_in_by_id`, `checked_in_at` |                                                         |
| `anonymized_at`       |                                                                       |

An offer isn't a separate status. A waitlisted RSVP with `offer_held_until` in the future is holding a spot.

Indexes:

- Unique on `(event_occurrence_id, lower(email))` where `status <> 'cancelled'` and `email IS NOT NULL`, so the same person can't RSVP twice.
- Unique on `(event_occurrence_id, user_id)` where `status <> 'cancelled'` and `user_id IS NOT NULL`.
- `(event_occurrence_id, status, waitlisted_at)` for wait list ordering.

### Models and services

- `Rsvp` model with scopes (`holding_spot`, `waitlisted`, `active`, `guests`) and status predicates.
- `EventOccurrence#effective_capacity`, `#spots_taken`, `#spots_remaining`, `#full?`, `#rsvp_open?`.
- `RsvpService` in `app/services/` does all the state changes inside the lock: `create`, `confirm_pending`, `cancel`, `claim`, `promote`, and `fill_open_spots`. The service applies the wait list mode. Controllers and jobs call this service and never update RSVP status directly.
- Journal entries (`EventJournal`) when hosts or admins cancel, promote, add people, or check people in.

## Emails

All emails follow the existing email test mode (`SiteConfig#email_test_mode_*`). That logic is currently in `HostReminderNotificationJob#determine_recipient_email`, so it moves into a shared concern first.

### `RsvpMailer` (attendees)

| Email                  | When                                                       | Contents                                         |
|------------------------|------------------------------------------------------------|--------------------------------------------------|
| `confirm_email`        | Guest RSVP                                                 | Link to confirm                                  |
| `login_required`       | Guest RSVP whose email matches an existing account         | Link to log in and RSVP                          |
| `confirmed`            | RSVP confirmed                                             | Details, manage link, `.ics` attachment          |
| `waitlisted`           | Added to the wait list                                     | Position, manage link                            |
| `spot_open`            | First come mode, or the last-call window                   | Claim link, "first to claim it gets it"          |
| `spot_held`            | Sequential mode hold                                       | Accept / decline buttons, deadline               |
| `offer_reminder`       | Once per person, only while a spot is still open           | Same claim link                                  |
| `reminder`             | 7 days, 1 day, and the morning of                          | Details, manage link                             |
| `release_nag`          | Capacity-limited and the event is full or has a wait list | "Can't make it? Release your spot" one-click link |
| `cancelled_by_host`    | Host or admin cancelled the RSVP                           | Optional reason                                  |
| `occurrence_changed`   | Occurrence cancelled, relocated, or its time changed       | New details, or the cancellation notice          |

The `release_nag` email is combined with the 1-day reminder, so people don't get two emails on the same day.

### `RsvpHostMailer` (hosts who turned on `notify_on_rsvp`)

- `rsvp_activity`: one email for each new confirmed RSVP, cancellation, or wait list join, with the name, the action, and the current counts.

## Jobs

The schedules go in `config/sidekiq.yml`.

- `RsvpReminderJob`, hourly. It sends attendee reminders and the release nag where the reminder time has passed and the `*_sent_at` column isn't set.
- `RsvpOfferJob`, every 15 minutes. It releases expired sequential holds, sends offer reminders, and calls `RsvpService#fill_open_spots`.
- `RsvpCleanupJob`, daily. It deletes unconfirmed pending RSVPs, finalizes check-in (marks no-shows), and anonymizes guest data past the retention period.
- `RsvpService` calls `fill_open_spots` immediately after any cancellation or capacity increase.

## Occurrence lifecycle integration

- **Cancelled**: email everyone on the RSVP list and wait list, and mark their RSVPs `cancelled` with `cancelled_via: occurrence_cancelled`. Reactivating the occurrence does not restore them. The email says so.
- **Postponed**: `postpone!` creates a new occurrence. Move the RSVPs to the new occurrence and email everyone the new date, so their links keep working. Clear any holds and re-check capacity against the new occurrence.
- **Relocated** or **time edited**: email everyone with the change.
- **Capacity reduced** below the number of confirmed spots: nobody is bumped. New RSVPs go to the wait list until the count drops. Hosts see a warning.
- **Capacity increased**: run `fill_open_spots`.
- **Event or occurrence soft-deleted**: treat it the same as cancelled.

## UI

### Public occurrence / event page

- RSVP button that shows the count, for example "RSVP (8 of 20 spots left)", or "Full: join wait list".
- If the viewer has already RSVP'd: their status, wait list position, and a cancel button.
- Guest form (public events only): name, email, and a honeypot field. Rate limited with Rails 8 `rate_limit`.

### Management page (`/rsvps/:token`)

- Status, event details, cancel button, claim / decline when a spot is available, and a toggle to opt out of reminders.

### Host / admin view (on the occurrence page, plus `/occurrences/:slug/rsvps`)

- Tabs for confirmed, wait list (in order, showing any active hold), pending, and cancelled.
- Actions: cancel (with an optional reason that is emailed), promote from the wait list, resend confirmation, and add a person manually.
- Check-in view during the check-in window.
- CSV export (names, status, attendance; emails only for admins).
- Authorization reuses `Event#hosted_by?` (hosts and admins). The email columns are shown only when `current_user.admin?`.

### Event form

- An "RSVPs" section with the enable toggle, capacity, wait list toggle, wait list mode, and the RSVP cutoff. On the occurrence edit form, a capacity override and a toggle to turn RSVPs off for that date.
- In the host list, each host can toggle "Email me about RSVPs" for themselves.

### Dashboard

- "My RSVPs" list for logged-in users.
- Hosts see RSVP counts for their upcoming occurrences.

## Phases (each one commits separately with tests)

1. **Schema and models**: migrations, `Rsvp` model, capacity methods on the occurrence, `RsvpService` with locking, and model/service tests (including concurrency on the last seat).
2. **RSVP flow**: public RSVP and cancel for logged-in users and guests, the login requirement for guests who have an account, linking guest RSVPs to an account at login, the management page, the confirmation and wait list emails, and the `.ics` attachment.
3. **Host / admin lists**: the list view, cancel / promote / add actions, the CSV export, the name-only privacy rule, host RSVP notifications, and journal entries.
4. **Wait list**: both modes, claiming spots, sequential holds and their expiry, the last-call switch, the one offer reminder, and `RsvpOfferJob`.
5. **Reminders and the release nag**: `RsvpReminderJob`, reminder opt-out, and idempotency tests.
6. **Lifecycle integration**: cancellation, postponement, relocation, time change, and capacity changes.
7. **Check-in and cleanup**: the check-in view, no-show finalization, the no-show counts in the host list, removing pending RSVPs, guest anonymization, and `RsvpCleanupJob`.
8. **Polish**: dashboard sections, event form UI, site config settings, the docs update, a CHANGELOG entry, and the version bump to 0.25.0.
