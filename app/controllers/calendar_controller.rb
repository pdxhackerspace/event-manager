class CalendarController < ApplicationController
  before_action :allow_iframe, only: :embed

  def index
    @embed = false
    setup_view_params
    fetch_occurrences(public_only: !current_user)

    respond_to do |format|
      format.html
      format.json { render json: calendar_json_response }
    end
  end

  def embed
    @embed = true
    setup_view_params
    fetch_occurrences(public_only: true)
    render layout: 'embed'
  end

  def ical
    # Get all public event occurrences (next 6 months)
    six_months_from_now = 6.months.from_now
    @occurrences = EventOccurrence
                   .joins(:event)
                   .where(events: { visibility: 'public', status: 'active', draft: false })
                   .where('event_occurrences.occurs_at >= ?', Time.current)
                   .where('event_occurrences.occurs_at <= ?', six_months_from_now)
                   .where(event_occurrences: { status: 'active' })
                   .includes(event: %i[location hosts user])
                   .order(:occurs_at)
                   .limit(500)

    calendar = Icalendar::Calendar.new
    calendar.prodid = "-//#{@site_config&.organization_name || 'EventManager'}//Calendar//EN"

    @occurrences.each do |occurrence|
      calendar.event do |e|
        e.dtstart = Icalendar::Values::DateTime.new(occurrence.occurs_at)
        e.dtend = Icalendar::Values::DateTime.new(occurrence.occurs_at + occurrence.duration.minutes)
        e.summary = occurrence.event.title
        e.description = occurrence.description
        e.url = event_url(occurrence.event)

        # Add location if present
        e.location = occurrence.event_location.name if occurrence.event_location

        # Add organizer/hosts
        if occurrence.event.hosts.any?
          host_names = occurrence.event.hosts.map { |h| h.name || h.email }.join(', ')
          e.organizer = "Hosts: #{host_names}"
        end

        # Unique identifier for this occurrence
        e.uid = "occurrence-#{occurrence.id}@#{request.host}"
        e.dtstamp = Icalendar::Values::DateTime.new(occurrence.updated_at)
      end
    end

    calendar.publish

    respond_to do |format|
      format.ics { render plain: calendar.to_ical, content_type: 'text/calendar' }
    end
  end

  private

  def setup_view_params
    @view = params[:view] || 'calendar'
    @current_month = params[:month] ? Date.parse(params[:month]) : Date.current.beginning_of_month
    @open_to_filter = params[:open_to]
  end

  def fetch_occurrences(public_only:)
    if @view == 'calendar'
      fetch_calendar_occurrences(public_only: public_only)
    else
      fetch_list_occurrences(public_only: public_only)
    end
  end

  def fetch_calendar_occurrences(public_only:)
    calendar_start = @current_month.beginning_of_month.beginning_of_week(:sunday)
    calendar_end = @current_month.end_of_month.end_of_week(:sunday)

    @occurrences = base_occurrence_query(public_only: public_only)
                   .where('event_occurrences.occurs_at >= ? AND event_occurrences.occurs_at <= ?',
                          calendar_start.beginning_of_day, calendar_end.end_of_day)

    @occurrences = apply_open_to_filter(@occurrences)
    @occurrences_by_date = @occurrences.group_by { |occ| occ.occurs_at.to_date }
  end

  def fetch_list_occurrences(public_only:)
    @occurrences = base_occurrence_query(public_only: public_only)
                   .where('event_occurrences.occurs_at >= ?', Time.current.beginning_of_day)
                   .limit(50)

    @occurrences = apply_open_to_filter(@occurrences)
    @occurrences_by_month = @occurrences.group_by { |occ| occ.occurs_at.beginning_of_month }
  end

  def base_occurrence_query(public_only:)
    query = EventOccurrence
            .joins(:event)
            .where(event_occurrences: { status: %w[active postponed cancelled relocated] })
            .includes(event: %i[hosts user], banner_image_attachment: :blob)
            .order(:occurs_at)

    if public_only
      query.where(events: { visibility: 'public', draft: false })
    else
      query.where(event: policy_scope(Event))
    end
  end

  def apply_open_to_filter(occurrences)
    return occurrences if @open_to_filter.blank?

    occurrences.where(events: { open_to: @open_to_filter })
  end

  def allow_iframe
    response.headers.delete('X-Frame-Options')
  end

  def calendar_json_response
    now = Time.current
    public_occurrences = EventOccurrence
                         .joins(:event)
                         .where(events: { visibility: 'public', draft: false })
                         .not_yet_ended(now)
                         .includes(event: [:hosts, { banner_image_attachment: :blob }], banner_image_attachment: :blob)
                         .order(:occurs_at)
                         .limit(100)

    occurrences_data = public_occurrences.map { |occ| build_calendar_occurrence_json(occ, now) }

    {
      occurrences: occurrences_data,
      generated_at: Time.current.iso8601,
      count: occurrences_data.count
    }
  end

  def build_calendar_occurrence_json(occ, now)
    occurrence_end = occ.occurs_at + occ.duration.minutes

    {
      id: occ.id,
      slug: occ.slug,
      occurs_at: occ.occurs_at.iso8601,
      status: occ.status,
      duration: occ.duration,
      description: occ.description,
      postponed_until: occ.postponed_until&.iso8601,
      cancellation_reason: occ.cancellation_reason,
      relocated_to: occ.relocated_to,
      in_progress: now >= occ.occurs_at && now < occurrence_end,
      open_to: occ.event.open_to,
      location: occ.event_location ? { id: occ.event_location.id, name: occ.event_location.name } : nil,
      has_custom_location: occ.location_id.present?,
      banner_url: occ.banner.attached? ? url_for(occ.banner) : nil,
      has_custom_banner: occ.banner_image.attached?,
      event: build_calendar_event_info(occ.event)
    }
  end

  def build_calendar_event_info(event)
    {
      id: event.id,
      slug: event.slug,
      title: event.title,
      recurrence_type: event.recurrence_type,
      more_info_url: event.more_info_url,
      visibility: event.visibility,
      open_to: event.open_to,
      location: event.location ? { id: event.location.id, name: event.location.name } : nil,
      hosts: event.hosts.map { |h| h.name || h.email }
    }
  end
end
