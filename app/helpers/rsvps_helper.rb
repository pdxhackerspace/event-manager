module RsvpsHelper
  def rsvp_collecting?(occurrence)
    return false if occurrence.nil? || occurrence.rsvp_disabled?

    occurrence.event.rsvp_enabled? && SiteConfig.current.rsvps_enabled?
  end

  def rsvp_required_badge(extra_class: nil)
    tag.span('RSVP required', class: ['badge bg-primary', extra_class].compact.join(' '))
  end

  def rsvp_capacity_summary(occurrence)
    capacity = occurrence.effective_capacity
    return 'No capacity limit' if capacity.nil?

    left = occurrence.spots_remaining
    "#{left} of #{capacity} #{'spot'.pluralize(capacity)} left"
  end

  def rsvp_action_label(occurrence)
    remaining = occurrence.spots_remaining
    return 'RSVP' if remaining.nil? || remaining.positive?
    return 'Join the wait list' if occurrence.event.waitlist_enabled?

    'Full'
  end

  def rsvp_login_path(occurrence, on_event_page:)
    return_to = event_path(occurrence.event, anchor: 'rsvp') if on_event_page
    return_to ||= event_occurrence_path(occurrence, anchor: 'rsvp')
    new_user_session_path(rsvp_occurrence_id: occurrence.id, return_to: return_to)
  end

  def rsvp_status_label(rsvp)
    case rsvp.status
    when 'confirmed' then 'You are confirmed'
    when 'waitlisted' then "You are ##{rsvp.waitlist_position} on the wait list"
    when 'pending' then 'Check your email to confirm this RSVP'
    else 'This RSVP is cancelled'
    end
  end
end
