# Machine-readable event feeds: RSS, iCal, and the JSON the e-ink signs poll.
#
# All public and read-only, sharing none of the CRUD or authorization behavior
# in EventsController. Route paths and helper names are unchanged from when
# these lived there.
class EventFeedsController < ApplicationController
  RSS_EVENT_LIMIT = 50
  EVENT_OCCURRENCE_LIMIT = 20
  ICAL_OCCURRENCE_LIMIT = 50

  def rss
    # The template renders each event's banner, so the image associations behind
    # Event#banner_image have to come along or each item costs extra queries.
    @events = Event.where(status: 'active', draft: false)
                   .where(visibility: %w[public members])
                   .includes(:user, :hosts, :location,
                             event_images: { image_attachment: :blob },
                             fixed_event_image: { image_attachment: :blob })
                   .order(updated_at: :desc)
                   .limit(RSS_EVENT_LIMIT)

    @next_occurrence_by_event = next_occurrence_by_event(@events)

    respond_to do |format|
      format.rss { render layout: false }
    end
  end

  def event_rss
    @event = Event.friendly_find(params[:id])

    # Only published public/members events get a per-event feed.
    if @event.draft? || @event.visibility == 'private'
      head :not_found
      return
    end

    @occurrences = @event.occurrences.upcoming.limit(EVENT_OCCURRENCE_LIMIT)

    respond_to do |format|
      format.rss { render layout: false }
    end
  end

  def eink
    render json: EinkFeedSerializer.new.as_json
  end

  def ical
    @event = Event.find_by!(ical_token: params.expect(:token))

    # Draft events get an empty feed so the token stays valid once they publish.
    occurrences = @event.draft? ? EventOccurrence.none : @event.event_occurrences.upcoming.limit(ICAL_OCCURRENCE_LIMIT)

    builder = IcalBuilder.new(host: request.host,
                              organization_name: @site_config&.organization_name,
                              name: @event.draft? ? nil : @event.title,
                              publish: true)

    occurrences.each do |occurrence|
      builder.add_occurrence(occurrence, page_url: event_occurrence_url(occurrence))
    end

    respond_to do |format|
      format.ics { render plain: builder.to_ical, content_type: 'text/calendar' }
    end
  end

  private

  # The feed shows each event's next date, which would otherwise be a query per
  # item in the template.
  def next_occurrence_by_event(events)
    return {} if events.empty?

    EventOccurrence.upcoming
                   .where(event_id: events.map(&:id))
                   .first_per_event
                   .index_by(&:event_id)
  end
end
