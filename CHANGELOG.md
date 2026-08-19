# Changelog

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
