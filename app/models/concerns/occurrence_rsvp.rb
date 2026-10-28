module OccurrenceRsvp
  extend ActiveSupport::Concern

  def ends_at
    occurs_at + duration.minutes
  end

  def effective_capacity
    capacity_override.nil? ? event.capacity : capacity_override
  end

  def spots_taken(except: nil)
    confirmed = rsvps.where(status: 'confirmed')
    held = rsvps.where(status: 'waitlisted').where('offer_held_until > ?', Time.current)
    if except
      confirmed = confirmed.where.not(id: except.id)
      held = held.where.not(id: except.id)
    end
    confirmed.count + held.count
  end

  def spots_remaining
    cap = effective_capacity
    return nil if cap.nil?

    [cap - spots_taken, 0].max
  end

  def full?
    cap = effective_capacity
    cap.present? && spots_taken >= cap
  end

  def rsvp_open?(at = Time.current)
    return false unless SiteConfig.current.rsvps_enabled?
    return false unless event.rsvp_enabled?
    return false if rsvp_disabled?
    return false unless self.class::LISTABLE_STATUSES.include?(status)
    return false if event.draft? || event.status != 'active' || event.deleted? || deleted?
    return false if ends_at <= at

    at < occurs_at - event.rsvp_closes_minutes_before.to_i.minutes
  end

  def checkin_open?(at = Time.current)
    at.between?(occurs_at - 1.hour, ends_at + 12.hours)
  end

  def waitlist_last_call?(at = Time.current)
    occurs_at <= at + SiteConfig.current.rsvp_last_call_hours.to_i.hours
  end

  def effective_waitlist_mode(at = Time.current)
    return 'first_come' if waitlist_last_call?(at) || !event.waitlist_enabled?

    event.waitlist_mode
  end

  def manageable_until?(at = Time.current)
    ends_at > at
  end
end
