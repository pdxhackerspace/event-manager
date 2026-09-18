# The full event shape in the `events` array of /events.json.
#
# Scheduling fields (visibility, recurrence_type, start_time) stay visible for
# non-public events so consumers can still see the space is booked; everything
# descriptive is masked.
class EventFeedSerializer < FeedSerializer
  def as_json(*)
    public_event = record.public?

    {
      id: record.id,
      slug: record.slug,
      title: public_event ? record.title : 'Private Event',
      description: public_event ? record.description : nil,
      more_info_url: public_event ? record.more_info_url : nil,
      visibility: record.visibility,
      open_to: public_event ? record.open_to : nil,
      recurrence_type: record.recurrence_type,
      start_time: record.start_time.iso8601,
      duration: public_event ? record.duration : nil,
      requires_mask: public_event ? record.requires_mask : nil,
      hosts: public_event ? host_names(record) : [],
      location: public_event ? location_json(record.location) : nil,
      banner_url: public_event ? banner_url(fallback_image) : nil,
      spectra6_banner_url: public_event ? spectra6_banner_url(fallback_image) : nil
    }
  end

  private

  def fallback_image
    record.fallback_event_image&.image
  end
end
