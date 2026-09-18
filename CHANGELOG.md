# Changelog

## [v0.22.1] - 2026-09-18

### Fixed
- E-ink banner variants are generated again. `Spectra6BannerJob` built its storage key by joining the original key's directory, which for a normal upload is `.`, producing a `./spectra6-7.3/...` key that Active Storage rejects as a path traversal segment. Every run raised, so no event ever had a Spectra6 banner and the feeds always fell back to the full-size image. Run `bin/rails banners:generate_spectra6` to backfill
- Re-running `banners:generate_spectra6` replaces an existing variant instead of colliding with its storage key
- Deleting a user no longer fails outright. `event_journals.user_id` was `NOT NULL` while the association declared `dependent: :nullify`, so removing anyone who had ever edited an event raised a database error. Journal entries now outlive the account, as the audit log intended. (Users who created events are still held back by the events foreign key, which is a separate question)

### Added
- Test coverage for the activity journal and event host controllers, both of which were previously untested, and for `Spectra6BannerJob` end to end

## [v0.22.0] - 2026-09-18

### Fixed
- Co-hosts can view the private and draft events they host. Anyone added as a host could already edit, postpone, and cancel such an event but got "not authorized" trying to open it, and it never appeared in their event list

### Changed
- The events, users, and locations lists are paginated. The events list previously loaded every future occurrence of every event and sorted them in memory on each request, so the work grew with the whole calendar rather than with the page being shown
- Ordering the events list by each event's next date happens in the database, so pages stay cheap as more occurrences accumulate
- The public `/events.json`, `/events/eink`, and `/events/rss` feeds issue a fixed number of queries instead of one or more per event. They were looking up each event's e-ink banner variant, pooled images, and next date individually
- `/events.json` no longer runs the queries for the paginated HTML page it doesn't render
- The user list shows event counts from a single grouped query rather than one count per row

### Added
- Test coverage is measured and enforced. SimpleCov was a listed dependency that nothing ever loaded; `COVERAGE=1 bundle exec rspec` now reports coverage, and CI fails if it drops below the current level

## [v0.21.0] - 2026-09-18

### Changed
- The event wizard has a new **Images** step between Details and Scheduling holding the whole image pool, so images are no longer pinned above the wizard alongside whichever step happens to be open. Creating and editing an event walk the same five steps
- Actions taken in the image pool return to the Images step rather than to the top of the wizard

## [v0.20.0] - 2026-09-18

### Fixed
- Banner images picked while creating an event are actually uploaded. The event form was never marked as multipart, so the browser dropped the files and the new event ended up with an empty image pool
- Images picked in the image pool but never submitted with "Add to Pool" are uploaded when the event is saved, instead of being silently discarded
- Images uploaded to a pool that already has images are numbered from the next free position rather than skipping one

### Changed
- Creating and editing an event now present the same Image Pool section above the wizard. The separate "Banner Images" field on the wizard's Details step is gone
- Uploads submitted with the event form are added to the pool on edit as well as on create

### Added
- Selection mode can be chosen while creating an event rather than only afterwards

## [v0.19.5] - 2026-08-18

### Security
- Rate limits can no longer be bypassed by forging a request header. Visitor addresses are resolved by skipping the proxies listed in `config/trusted_proxies.yml`, and the localhost exemption now requires a genuine local connection, so a forged header can neither claim an exempt address nor evade login and lockout limits by rotating fake ones

## [v0.19.4] - 2026-08-18

### Fixed
- Images no longer come up blank or missing on image-heavy pages: rate limiting counted every image request against the same per-visitor page budget, so viewing a few events with a full image pool returned throttled responses that browsers render as broken images and that quietly started working again minutes later
- Rate limits are applied per visitor again rather than collectively. Behind Cloudflare and the reverse proxy, every request looked like it came from a Cloudflare edge address, so all visitors shared a single budget
- Sidekiq can read and write uploaded images, so background image processing no longer fails on a missing storage volume
- Release tags are named `v0.19.4` rather than `vv0.19.4`; the production workflow was prefixing a `v` onto a VERSION file that already had one
- CI gives each parallel test process its own database. Both processes shared one, so they intermittently deadlocked against each other and failed builds for reasons unrelated to the code under test

### Changed
- Image previews load a scaled-down version instead of the full-resolution original, so the image pool, event cards, calendar thumbnails, and pickers load a fraction of the data they used to
- Previews load as they scroll into view rather than all at once
- Images are delivered in one request instead of two and are cached by the browser and CDN, so revisiting a page no longer re-downloads every image
- The site runs multiple web workers by default, configurable with `WEB_CONCURRENCY`

### Added
- `rails images:preprocess_variants` generates preview sizes for images uploaded before previews existed
- [docs/IMAGE_DELIVERY.md](docs/IMAGE_DELIVERY.md) documents how images are served, what the reverse proxy needs to pass through, and how to diagnose missing images

## [v0.19.3] - 2026-08-17

### Fixed
- Calendar downloads and iCal feeds no longer shift event times: dates are now written as unambiguous UTC instants, so an event at 6:30 PM Pacific imports as 6:30 PM Pacific instead of drifting by the UTC offset
- Subscribed calendars outside the site's time zone show the correct start time rather than the local wall clock
- Occurrence status is mapped to a value the iCalendar standard allows, so cancelled and postponed events display correctly instead of being ignored
- Per-event feeds give each occurrence a stable identifier, so subscribers no longer accumulate duplicate copies on every refresh

### Changed
- Feeds and downloads carry a calendar name and display time zone, and every entry links back to its own occurrence page

### Added
- Calendar exports share a single builder, so the download button, the site-wide feed, the per-event feed, and the Google/Outlook/Yahoo links stay consistent

## [v0.19.2] - 2026-08-16

### Fixed
- README workflow badges now point at the correct workflows so CI, lint, and Docker build show accurate status

## [v0.19.1] - 2026-08-16

### Added
- README badges for CI, lint, Docker build, Ruby version, Rails version, and MIT license

## [v0.19.0] - 2026-08-16

### Added
- Reassign Existing Occurrences button in the image pool to apply the saved selection mode to all non-custom occurrences

### Fixed
- Occurrence edits no longer re-roll or advance the image cycle when the inherit option is unchanged
- Switching an occurrence from a custom image back to inherit advances the cycle index in cycle mode
- Image pool settings, reassign, and delete actions use separate forms instead of invalid nested forms
- Occurrence image reassignment follows schedule order (`occurs_at`) rather than database id order
- Pool image deletion clears references on soft-deleted occurrences so foreign keys do not block removal
- Event image pool migration sets `fixed_event_image_id` on the correct event after repointing banner attachments
- `bin/rubocop-local` rebuilds its cached image when the Ruby version or gems change, instead of silently reusing an image built on an older Ruby

## [v0.18.0] - 2026-08-16

### Added
- Event image pool: upload multiple banner images per event, reorder them, and remove images from the pool
- Image selection modes for new occurrences: fixed, random (avoid immediate repeat), or cycle through the pool in order
- Occurrence image editing: inherit auto-assigned image, pick from pool, or upload a custom image (optionally add to pool)
- Data migration moves existing event and occurrence banner attachments into the new pool on deploy

## [v0.13.2] - Thu Mar  5 09:13:59 PST 2026
