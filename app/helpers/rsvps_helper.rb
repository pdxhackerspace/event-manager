module RsvpsHelper
  def rsvp_action_label(occurrence)
    remaining = occurrence.spots_remaining
    return 'RSVP' if remaining.nil?
    return 'Full' if remaining.zero? && !occurrence.event.waitlist_enabled?

    if remaining.zero?
      'Full: join the wait list'
    else
      "RSVP (#{remaining} of #{occurrence.effective_capacity} #{"spot".pluralize(occurrence.effective_capacity)} left)"
    end
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
