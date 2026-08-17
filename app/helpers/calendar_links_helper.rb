# frozen_string_literal: true

# Helper methods for generating calendar service URLs (Google, Outlook, Yahoo, Apple, etc.)
module CalendarLinksHelper
  # Generate Apple Calendar URL (downloads .ics file)
  def apple_calendar_url(occurrence)
    # This returns the URL to download the .ics file for the occurrence
    Rails.application.routes.url_helpers.ical_event_occurrence_path(occurrence, format: :ics)
  end

  # Generate Google Calendar URL for an event occurrence
  def google_calendar_url(occurrence)
    event = occurrence.event
    start_time = occurrence.occurs_at.utc
    end_time = (start_time + occurrence.duration.minutes)

    params = {
      action: 'TEMPLATE',
      text: event.title,
      dates: "#{format_gcal_time(start_time)}/#{format_gcal_time(end_time)}",
      details: build_calendar_description(occurrence),
      location: occurrence.event_location&.name || '',
      sf: 'true'
    }

    "https://calendar.google.com/calendar/render?#{params.to_query}"
  end

  # Generate Outlook.com calendar URL for an event occurrence
  def outlook_calendar_url(occurrence)
    build_outlook_url(occurrence, 'https://outlook.live.com')
  end

  # Generate Office 365 calendar URL for an event occurrence
  def office365_calendar_url(occurrence)
    build_outlook_url(occurrence, 'https://outlook.office.com')
  end

  # Generate Yahoo Calendar URL for an event occurrence
  def yahoo_calendar_url(occurrence)
    event = occurrence.event
    start_time = occurrence.occurs_at.utc
    duration_hours = occurrence.duration / 60
    duration_mins = occurrence.duration % 60

    params = {
      v: 60,
      title: event.title,
      st: start_time.strftime('%Y%m%dT%H%M%SZ'),
      dur: format('%<hours>02d%<mins>02d', hours: duration_hours, mins: duration_mins),
      desc: build_calendar_description(occurrence),
      in_loc: occurrence.event_location&.name || ''
    }

    "https://calendar.yahoo.com/?#{params.to_query}"
  end

  private

  def build_outlook_url(occurrence, base_url)
    event = occurrence.event
    start_time = occurrence.occurs_at.utc
    end_time = (start_time + occurrence.duration.minutes)

    params = {
      path: '/calendar/action/compose',
      rru: 'addevent',
      subject: event.title,
      startdt: start_time.iso8601,
      enddt: end_time.iso8601,
      body: build_calendar_description(occurrence),
      location: occurrence.event_location&.name || ''
    }

    "#{base_url}/calendar/0/deeplink/compose?#{params.to_query}"
  end

  def format_gcal_time(time)
    time.strftime('%Y%m%dT%H%M%SZ')
  end

  def build_calendar_description(occurrence)
    IcalBuilder.description_for(occurrence, page_url: occurrence_page_url(occurrence))
  end

  def occurrence_page_url(occurrence)
    Rails.application.routes.url_helpers.event_occurrence_url(occurrence, host: calendar_link_host)
  end

  def calendar_link_host
    ENV.fetch('APP_HOST', 'localhost:3000')
  end
end
