# Builds the public /events.json payload: every published, active event with an
# occurrence that has not yet ended, plus those occurrences.
class EventsFeedSerializer
  # fallback_event_image reads fixed_event_image first, so that association has
  # to be preloaded too or it costs a query per event.
  EVENT_BANNER_INCLUDES = [
    :hosts,
    :location,
    { event_images: { image_attachment: :blob }, fixed_event_image: { image_attachment: :blob } }
  ].freeze

  def initialize(url_for:, now: Time.current)
    @url_for = url_for
    @now = now
  end

  def as_json(*)
    occurrences = load_occurrences
    events = load_events
    spectra6 = Spectra6BannerLookup.new(banner_attachments(events, occurrences))

    events_data = events.map do |event|
      EventFeedSerializer.new(event, url_for: @url_for, spectra6: spectra6).as_json
    end
    occurrences_data = occurrences.map do |occurrence|
      OccurrenceFeedSerializer.new(occurrence, url_for: @url_for, spectra6: spectra6, now: @now).as_json
    end

    {
      events: events_data,
      occurrences: occurrences_data,
      generated_at: Time.current.iso8601,
      event_count: events_data.count,
      occurrence_count: occurrences_data.count
    }
  end

  private

  # Occurrences in progress or upcoming, using the app timezone and the
  # occurrence's effective duration.
  def load_occurrences
    EventOccurrence
      .joins(:event)
      .where(events: { draft: false, status: 'active' })
      .not_yet_ended(@now)
      .includes(event: EVENT_BANNER_INCLUDES)
      .includes(event_image: { image_attachment: :blob })
      .order(occurs_at: :asc)
      .to_a
  end

  def load_events
    Event
      .where(draft: false, status: 'active')
      .joins(:occurrences)
      .merge(EventOccurrence.not_yet_ended(@now))
      .distinct
      .includes(EVENT_BANNER_INCLUDES)
      .order(:title)
      .to_a
  end

  # Every attachment the serializers might ask for a Spectra6 variant of, so
  # Spectra6BannerLookup resolves them in one query instead of one per row.
  def banner_attachments(events, occurrences)
    event_banners = events.map { |event| event.fallback_event_image&.image }
    occurrence_banners = occurrences.flat_map do |occurrence|
      [occurrence.banner, occurrence.event.fallback_event_image&.image]
    end

    (event_banners + occurrence_banners).compact
  end
end
