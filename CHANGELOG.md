# Changelog

## [v0.19.0] - 2026-08-16

### Added
- Reassign Existing Occurrences button in the image pool to apply the saved selection mode to all non-custom occurrences

### Fixed
- Occurrence edits no longer re-roll or advance the image cycle when the inherit option is unchanged
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
