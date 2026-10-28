class RsvpReminderJob < ApplicationJob
  queue_as :mailers

  def perform
    Rsvp.confirmed.where(reminders_opted_out: false).includes(event_occurrence: :event).find_each do |rsvp|
      send_due_reminder(rsvp)
    end
  end

  private

  def send_due_reminder(rsvp)
    occurrence = rsvp.event_occurrence
    return unless %w[active relocated].include?(occurrence.status)
    return if occurrence.occurs_at <= Time.current

    if day_of?(occurrence) && rsvp.reminder_day_of_sent_at.nil?
      deliver(rsvp, 'day_of', nag: rsvp.release_nag_sent_at.nil? && nag?(occurrence))
    elsif one_day?(occurrence) && rsvp.reminder_1d_sent_at.nil?
      deliver(rsvp, '1d', nag: nag?(occurrence))
    elsif week?(occurrence) && rsvp.reminder_7d_sent_at.nil?
      deliver(rsvp, '7d')
    end
  end

  def deliver(rsvp, kind, nag: false)
    RsvpNotifier.reminder(rsvp, kind: kind, nag: nag)
    now = Time.current
    rsvp.update!(
      reminder_7d_sent_at: rsvp.reminder_7d_sent_at || now,
      reminder_1d_sent_at: kind == '7d' ? rsvp.reminder_1d_sent_at : (rsvp.reminder_1d_sent_at || now),
      reminder_day_of_sent_at: kind == 'day_of' ? now : rsvp.reminder_day_of_sent_at,
      release_nag_sent_at: nag ? now : rsvp.release_nag_sent_at
    )
  end

  def week?(occurrence)
    Time.current >= occurrence.occurs_at - 7.days
  end

  def one_day?(occurrence)
    Time.current >= occurrence.occurs_at - 1.day
  end

  def day_of?(occurrence)
    Time.current >= occurrence.occurs_at.beginning_of_day && occurrence.occurs_at.to_date == Date.current
  end

  def nag?(occurrence)
    occurrence.effective_capacity.present? && (occurrence.full? || occurrence.rsvps.waitlisted.exists?)
  end
end
