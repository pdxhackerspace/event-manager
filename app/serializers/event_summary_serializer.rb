# The abbreviated event shape nested inside each occurrence in /events.json.
#
# Anything less permissive than "public" is reduced to a placeholder so the feed
# still exposes when the space is busy without leaking what is happening.
class EventSummarySerializer < FeedSerializer
  def as_json(*)
    return private_json unless record.public?

    {
      id: record.id,
      slug: record.slug,
      title: record.title,
      description: record.description,
      more_info_url: record.more_info_url,
      hosts: host_names(record),
      location: location_json(record.location),
      banner_url: banner_url(fallback_image),
      spectra6_banner_url: spectra6_banner_url(fallback_image)
    }
  end

  private

  def private_json
    {
      id: record.id,
      slug: record.slug,
      title: 'Private Event',
      description: nil,
      more_info_url: nil,
      hosts: [],
      location: nil,
      banner_url: nil,
      spectra6_banner_url: nil
    }
  end

  def fallback_image
    record.fallback_event_image&.image
  end
end
