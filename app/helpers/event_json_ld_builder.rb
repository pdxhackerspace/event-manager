class EventJsonLdBuilder
  def initialize(event, occurrence, site_config, helper)
    @event = event
    @occurrence = occurrence
    @site_config = site_config
    @helper = helper
  end

  def build
    start_time = @occurrence&.occurs_at || @event.start_time
    {
      '@context': 'https://schema.org',
      '@type': 'Event',
      name: @event.title,
      description: @event.description&.truncate(500),
      startDate: start_time.iso8601,
      endDate: (start_time + @event.duration.minutes).iso8601,
      eventStatus: event_status_schema,
      eventAttendanceMode: 'https://schema.org/OfflineEventAttendanceMode',
      location: location_schema,
      organizer: organizer_schema,
      url: @helper.event_url(@event),
      image: image_url,
      offers: offers_schema
    }.compact
  end

  private

  def event_status_schema
    status = (@occurrence || @event).status
    case status
    when 'cancelled' then 'https://schema.org/EventCancelled'
    when 'postponed' then 'https://schema.org/EventPostponed'
    else 'https://schema.org/EventScheduled'
    end
  end

  def location_schema
    location_name = @occurrence&.event_location&.name || @event.location&.name || site_name
    {
      '@type': 'Place',
      name: location_name,
      address: { '@type': 'PostalAddress', streetAddress: @site_config&.address || 'Portland, OR' }
    }
  end

  def organizer_schema
    { '@type': 'Organization', name: site_name, url: @site_config&.website_url || @helper.root_url }
  end

  def offers_schema
    { '@type': 'Offer', price: '0', priceCurrency: 'USD', availability: 'https://schema.org/InStock', url: @helper.event_url(@event) }
  end

  def image_url
    if @occurrence&.banner&.attached?
      @helper.preview_image_url(@occurrence.banner)
    elsif @event.banner_image.attached?
      @helper.preview_image_url(@event.banner_image)
    elsif @site_config&.banner_image&.attached?
      @helper.preview_image_url(@site_config.banner_image)
    end
  end

  def site_name
    @site_config&.organization_name || 'PDX Hackerspace'
  end
end
