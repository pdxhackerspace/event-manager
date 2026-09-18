# A single occurrence in the `occurrences` array of /events.json.
#
# Times are always exposed, even for non-public events, so consumers can tell
# the space is in use. Descriptive fields are masked.
class OccurrenceFeedSerializer < FeedSerializer
  def initialize(record, url_for:, spectra6:, now: Time.current)
    super(record, url_for: url_for, spectra6: spectra6)
    @now = now
  end

  def as_json(*)
    public_event = event.public?
    local_occurs_at = record.occurs_at.in_time_zone(Time.zone)

    {
      id: record.id,
      slug: record.slug,
      occurs_at: record.occurs_at.iso8601,
      occurs_at_unix: record.occurs_at.to_i,
      ends_at_unix: ends_at.to_i,
      weekday_abbr: local_occurs_at.strftime('%a'),
      month_abbr: local_occurs_at.strftime('%b'),
      duration: public_event ? record.duration : nil,
      is_cancelled: record.status == 'cancelled',
      is_postponed: record.status == 'postponed',
      in_progress: @now >= record.occurs_at && @now < ends_at,
      postponed_until: record.postponed_until&.iso8601,
      open_to: public_event ? event.open_to : nil,
      event: EventSummarySerializer.new(event, url_for: @url_for, spectra6: @spectra6).as_json,
      location: public_event ? location_json(record.event_location) : nil,
      description: public_event ? record.description : nil,
      banner_url: public_event ? banner_url(record.banner) : nil,
      spectra6_banner_url: public_event ? occurrence_spectra6_banner_url : nil
    }
  end

  private

  def event
    record.event
  end

  def ends_at
    @ends_at ||= record.occurs_at + record.duration.minutes
  end

  # An occurrence can carry an event_image whose file never attached, so fall
  # back to the event's banner rather than reporting no Spectra6 variant.
  def occurrence_spectra6_banner_url
    banner = record.banner
    return spectra6_banner_url(banner) if banner.attached?

    spectra6_banner_url(event.fallback_event_image&.image)
  end
end
