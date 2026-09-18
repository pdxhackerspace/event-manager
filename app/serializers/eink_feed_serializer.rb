# Minimal JSON feed for e-ink signs: the next few occurrences with just enough
# data to render a schedule.
#
# Only events opted into `sign_feed` show their details; the rest occupy a slot
# as "Private Event" so the sign still shows the space is booked.
class EinkFeedSerializer
  OCCURRENCE_LIMIT = 5

  def initialize(now: Time.current)
    @now = now
  end

  def as_json(*)
    {
      updated_at: @now.to_i,
      occurrences: load_occurrences.map { |occurrence| occurrence_json(occurrence) }
    }
  end

  private

  def load_occurrences
    EventOccurrence
      .joins(:event)
      .where(events: { draft: false, status: 'active' })
      .where(events: { visibility: %w[public members] })
      .where('event_occurrences.occurs_at > ?', @now)
      .includes(event: :location)
      .order(occurs_at: :asc)
      .limit(OCCURRENCE_LIMIT)
  end

  def occurrence_json(occurrence)
    event = occurrence.event
    show_details = event.sign_feed?

    entry = {
      start_time: occurrence.occurs_at.to_i,
      duration: occurrence.duration,
      name: show_details ? event.title : 'Private Event',
      open_to: show_details ? event.open_to : nil,
      location: show_details && event.location ? event.location.name : nil
    }

    entry.merge(show_details ? status_json(occurrence) : {})
  end

  def status_json(occurrence)
    case occurrence.status
    when 'cancelled'
      { cancelled: true }.merge(reason_json(occurrence))
    when 'postponed'
      postponed = { postponed: true }
      postponed[:postponed_until] = occurrence.postponed_until.to_i if occurrence.postponed_until
      postponed
    when 'relocated'
      relocated = { relocated: true }
      relocated[:relocated_to] = occurrence.relocated_to if occurrence.relocated_to.present?
      relocated.merge(reason_json(occurrence))
    else
      {}
    end
  end

  def reason_json(occurrence)
    return {} if occurrence.cancellation_reason.blank?

    { reason: occurrence.cancellation_reason }
  end
end
