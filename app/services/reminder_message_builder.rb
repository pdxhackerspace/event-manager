# rubocop:disable-next Metrics/ModuleLength
module ReminderMessageBuilder
  LINK_TEXT = 'More info →'.freeze

  # Returns { text: "...", link_url: "...", link_text: "More info →" }
  # message_type: :short (for Bluesky) or :long (for Slack/Instagram)
  # days_ahead: 6 for 6-day reminder, 1 for 1-day reminder
  def reminder_message_with_link(occurrence, label, days_ahead: nil, message_type: :short)
    # Determine days_ahead from label if not provided
    days_ahead ||= label.include?('day') && label.exclude?('1 day') ? 6 : 1

    case occurrence.status
    when 'cancelled'
      cancelled_message_parts(occurrence, message_type)
    when 'postponed'
      postponed_message_parts(occurrence, message_type)
    when 'relocated'
      relocated_message_parts(occurrence, message_type)
    else
      active_message_parts(occurrence, label, days_ahead, message_type)
    end
  end

  # Short message for Bluesky, Long for Slack/Instagram
  def short_reminder_message(occurrence, label, days_ahead: nil)
    parts = reminder_message_with_link(occurrence, label, days_ahead: days_ahead, message_type: :short)
    "#{parts[:text]} #{parts[:link_url]}"
  end

  def long_reminder_message(occurrence, label, days_ahead: nil)
    parts = reminder_message_with_link(occurrence, label, days_ahead: days_ahead, message_type: :long)
    "#{parts[:text]} #{parts[:link_url]}"
  end

  private

  def active_message_parts(occurrence, label, days_ahead, message_type)
    # Check for custom reminder message (occurrence's own or inherited from event)
    custom_message = get_custom_message(occurrence, days_ahead, message_type)

    message = custom_message.presence || generate_default_message(occurrence, label, message_type)

    { text: message, link_url: occurrence_url_for(occurrence), link_text: LINK_TEXT }
  end

  def get_custom_message(occurrence, days_ahead, message_type)
    # Use the "7d" (now 6-day) reminder for advance notices, "1d" for day-before
    if message_type == :short
      days_ahead > 1 ? occurrence.effective_reminder_7d_short : occurrence.effective_reminder_1d_short
    else
      days_ahead > 1 ? occurrence.effective_reminder_7d_long : occurrence.effective_reminder_1d_long
    end
  end

  def generate_default_message(occurrence, label, message_type)
    event = occurrence.event
    date_str = occurrence.occurs_at.strftime('%B %d, %Y')
    time_str = occurrence.occurs_at.strftime('%I:%M %p')
    duration_str = format_duration(occurrence.duration)

    # Format the timing phrase: "in 1 week", "in 1 day", but "today" or "tomorrow" without "in"
    timing = format_timing_phrase(label)

    if message_type == :short
      # Short message for Bluesky
      message = "#{event.title} is #{timing} at PDX Hackerspace on #{date_str} at #{time_str}."
      message += " Join us!" if message.length < 200
    else
      # Long message for Slack/Instagram
      message = "📅 #{event.title} is #{timing} at PDX Hackerspace!\n"
      message += "🕐 #{date_str} at #{time_str} (#{duration_str})\n"
      message += "📍 #{occurrence.event_location.name}\n" if occurrence.event_location.present?
      if event.description.present?
        desc = event.description.length > 400 ? "#{event.description[0..397]}..." : event.description
        message += "\n#{desc}"
      end
    end

    message
  end

  def format_timing_phrase(label)
    # Labels like "today" and "tomorrow" don't need "in" prefix
    # Labels like "1 week" and "1 day" should become "in 1 week" and "in 1 day"
    return label if %w[today tomorrow].include?(label.downcase)

    "in #{label}"
  end

  def cancelled_message_parts(occurrence, message_type)
    event, date_str, time_str = occurrence_info(occurrence)
    msg = message_type == :short ? short_cancelled(event, date_str, time_str) : long_cancelled(event, date_str, time_str, occurrence)
    { text: msg, link_url: occurrence_url_for(occurrence), link_text: LINK_TEXT }
  end

  def short_cancelled(event, date_str, time_str)
    msg = "⚠️ CANCELLED: #{event.title} on #{date_str} at #{time_str}."
    msg.length < 250 ? "#{msg} Sorry!" : msg
  end

  def long_cancelled(event, date_str, time_str, occurrence)
    msg = "⚠️ CANCELLED: #{event.title} scheduled for #{date_str} at #{time_str} has been cancelled."
    msg += "\nReason: #{occurrence.cancellation_reason}" if occurrence.cancellation_reason.present?
    "#{msg}\nWe apologize for any inconvenience."
  end

  def postponed_message_parts(occurrence, message_type)
    event, date_str, time_str = occurrence_info(occurrence)
    msg = message_type == :short ? short_postponed(event, date_str, occurrence) : long_postponed(event, date_str, time_str, occurrence)
    { text: msg, link_url: occurrence_url_for(occurrence), link_text: LINK_TEXT }
  end

  def short_postponed(event, date_str, occurrence)
    msg = "📅 POSTPONED: #{event.title} (was #{date_str})."
    occurrence.postponed_until.present? ? "#{msg} New date: #{occurrence.postponed_until.strftime('%B %d')}." : msg
  end

  def long_postponed(event, date_str, time_str, occurrence)
    msg = "📅 POSTPONED: #{event.title} originally scheduled for #{date_str} at #{time_str} has been postponed."
    return msg if occurrence.postponed_until.blank?

    "#{msg}\nNew date: #{occurrence.postponed_until.strftime('%B %d, %Y at %I:%M %p')}."
  end

  def relocated_message_parts(occurrence, message_type)
    event, date_str, time_str = occurrence_info(occurrence)
    msg = message_type == :short ? short_relocated(event, date_str, occurrence) : long_relocated(event, date_str, time_str, occurrence)
    { text: msg, link_url: occurrence_url_for(occurrence), link_text: LINK_TEXT }
  end

  def short_relocated(event, date_str, occurrence)
    msg = "📍 RELOCATED: #{event.title} on #{date_str}"
    occurrence.relocated_to.present? ? "#{msg} moved to #{occurrence.relocated_to}." : "#{msg} has moved."
  end

  def long_relocated(event, date_str, time_str, occurrence)
    msg = "📍 RELOCATED: #{event.title} on #{date_str} at #{time_str} has moved to a new location."
    msg += "\n📍 New venue: #{occurrence.relocated_to}" if occurrence.relocated_to.present?
    msg += "\nNote: #{occurrence.cancellation_reason}" if occurrence.cancellation_reason.present?
    msg += "\nThe event continues at the new location (no longer at our space)."
    msg
  end

  def occurrence_info(occurrence)
    [occurrence.event, occurrence.occurs_at.strftime('%B %d, %Y'), occurrence.occurs_at.strftime('%I:%M %p')]
  end

  def occurrence_url_for(occurrence)
    host = ENV.fetch('RAILS_HOST', ENV.fetch('HOST', 'localhost:3000'))
    protocol = ENV.fetch('RAILS_PROTOCOL', 'http')
    "#{protocol}://#{host}/occurrences/#{occurrence.slug}"
  end

  def format_duration(minutes)
    hours = minutes / 60
    mins = minutes % 60
    if hours.positive? && mins.positive?
      "#{hours}h #{mins}m"
    elsif hours.positive?
      "#{hours}h"
    else
      "#{mins}m"
    end
  end
end
