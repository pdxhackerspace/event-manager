# frozen_string_literal: true

# Sends email notifications to event hosts the day before Slack/social media reminders
# are scheduled to go out, giving them a chance to update the reminder message.
#
# This job runs daily and checks for events that will have reminders posted:
# - Tomorrow for 6-day reminders (event is 7 days away)
# - Tomorrow for 1-day reminders (event is 2 days away)
class HostReminderNotificationJob < ApplicationJob
  queue_as :mailers

  # Maps days until reminder posts -> days until event
  REMINDER_SCHEDULE = {
    7 => { reminder_days: 6, label: '6 days' },  # Tomorrow's 6-day reminder
    2 => { reminder_days: 1, label: '1 day' }    # Tomorrow's 1-day reminder
  }.freeze

  def perform
    @site_config = SiteConfig.current

    # Check if host email reminders are enabled at the site level
    unless @site_config.host_email_reminders_enabled?
      Rails.logger.info 'HostReminderNotificationJob: Host email reminders disabled in site config'
      return
    end

    # Check if either Slack or social reminders are enabled
    slack_enabled = @site_config.slack_enabled? && ENV['SLACK_WEBHOOK_URL'].present?
    social_enabled = @site_config.social_reminders_enabled?

    return unless slack_enabled || social_enabled

    log_test_mode_status
    Rails.logger.info 'HostReminderNotificationJob: Starting host reminder notifications'

    REMINDER_SCHEDULE.each do |days_until_event, info|
      send_notifications_for_events(days_until_event, info, slack_enabled, social_enabled)
    end

    Rails.logger.info 'HostReminderNotificationJob: Completed'
  end

  private

  def send_notifications_for_events(days_until_event, info, slack_enabled, social_enabled)
    target_date = Date.current + days_until_event.days
    start_time = target_date.beginning_of_day
    end_time = target_date.end_of_day

    occurrences = find_occurrences(start_time, end_time, slack_enabled, social_enabled)

    return if occurrences.empty?

    Rails.logger.info "HostReminderNotificationJob: Found #{occurrences.count} events " \
                      "#{days_until_event} days away (#{info[:label]} reminder tomorrow)"

    occurrences.each do |occurrence|
      notify_hosts_for_occurrence(occurrence, days_until_event, slack_enabled, social_enabled)
    end
  end

  def find_occurrences(start_time, end_time, slack_enabled, social_enabled)
    base_query = EventOccurrence
                 .joins(:event)
                 .where('event_occurrences.occurs_at >= ? AND event_occurrences.occurs_at <= ?',
                        start_time, end_time)
                 .where(event_occurrences: { status: 'active' })
                 .where(events: { status: 'active', draft: false })
                 .where(events: { visibility: %w[public members] })
                 .includes(event: :hosts)

    # Filter to events that have at least one reminder type enabled
    if slack_enabled && social_enabled
      base_query.where('events.slack_announce = ? OR events.social_reminders = ?', true, true)
    elsif slack_enabled
      base_query.where(events: { slack_announce: true })
    else
      base_query.where(events: { social_reminders: true })
    end
  end

  def notify_hosts_for_occurrence(occurrence, days_until_event, slack_enabled, social_enabled)
    event = occurrence.event

    event.hosts.each do |host|
      next unless host.email_reminders_enabled?

      # Send notification for each enabled reminder type
      send_notification(host, occurrence, 'slack', days_until_event) if slack_enabled && event.slack_announce?
      send_notification(host, occurrence, 'social', days_until_event) if social_enabled && event.social_reminders?
    end
  end

  def send_notification(host, occurrence, reminder_type, days_until_event)
    recipient_email = determine_recipient_email(host)

    HostReminderMailer.upcoming_reminder_notification(
      user: host,
      occurrence: occurrence,
      reminder_type: reminder_type,
      days_until_event: days_until_event,
      recipient_email: recipient_email
    ).deliver_later

    log_notification_queued(host, occurrence, reminder_type, recipient_email)
  rescue StandardError => e
    Rails.logger.error "HostReminderNotificationJob: Failed to send notification to #{host.email}: #{e.message}"
  end

  def determine_recipient_email(host)
    EmailTestMode.recipient_for(host.email)
  end

  def log_test_mode_status
    return unless @site_config.email_test_mode_enabled?

    Rails.logger.info "HostReminderNotificationJob: TEST MODE ENABLED - " \
                      "all emails will be sent to #{@site_config.email_test_mode_address}"
  end

  def log_notification_queued(host, occurrence, reminder_type, recipient_email)
    if recipient_email == host.email
      Rails.logger.info "HostReminderNotificationJob: Queued #{reminder_type} notification " \
                        "for #{host.email} about #{occurrence.event.title}"
    else
      Rails.logger.info "HostReminderNotificationJob: Queued #{reminder_type} notification " \
                        "for #{host.email} (TEST MODE: sent to #{recipient_email}) about #{occurrence.event.title}"
    end
  end
end
