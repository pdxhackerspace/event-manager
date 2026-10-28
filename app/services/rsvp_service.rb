class RsvpService
  include Seating

  Result = Data.define(:ok, :code, :rsvp) do
    def ok? = ok
  end

  def initialize(occurrence)
    @occurrence = occurrence
  end

  def create(user: nil, name: nil, email: nil, manual: false)
    email = email.to_s.strip.downcase
    return result(false, :closed) if !manual && !occurrence.rsvp_open?

    if user.nil? && account_exists?(email)
      return login_required(email) unless manual

      user = account_for(email)
    end
    return result(false, :host) if host_user?(user)

    occurrence.with_lock do
      existing = active_for(user:, email: email.presence || user&.email)
      return result(false, :duplicate, existing) if existing

      user ? create_member(user) : create_guest(name, email, manual:)
    end
  rescue ActiveRecord::RecordNotUnique
    result(false, :duplicate, active_for(user:, email:))
  end

  def confirm_pending!(rsvp)
    return result(false, :closed, rsvp) unless occurrence.manageable_until?

    occurrence.with_lock do
      rsvp.reload
      return result(true, :confirmed, rsvp) if rsvp.confirmed?
      return result(true, :waitlisted, rsvp) if rsvp.waitlisted?
      return result(false, :cancelled, rsvp) unless rsvp.pending?
      return result(false, :closed, rsvp) unless occurrence.rsvp_open?

      assign_seat!(rsvp)
    end
  end

  def claim!(rsvp)
    return result(false, :closed, rsvp) unless occurrence.manageable_until?

    occurrence.with_lock do
      rsvp.reload
      return result(true, :confirmed, rsvp) if rsvp.confirmed?
      return result(false, :invalid, rsvp) unless rsvp.waitlisted?
      return result(false, :taken, rsvp) if confirmed_full?
      return result(false, :held, rsvp) unless occurrence.spots_taken(except: rsvp) < capacity_or_infinity

      mark_confirmed(rsvp)
    end
  end

  def decline!(rsvp)
    return result(false, :closed, rsvp) unless occurrence.manageable_until?

    occurrence.with_lock do
      rsvp.reload
      return result(false, :invalid, rsvp) unless rsvp.waitlisted?

      rsvp.update!(offer_held_until: nil)
    end
    RsvpAllocator.new(occurrence).fill_open_spots
    result(true, :waitlisted, rsvp)
  end

  def cancel!(rsvp, actor: nil, via: 'self', reason: nil, reopen: true)
    return result(false, :closed, rsvp) if via == 'self' && !occurrence.manageable_until?

    occurrence.with_lock do
      rsvp.reload
      return result(true, :cancelled, rsvp) if rsvp.cancelled?

      rsvp.update!(status: 'cancelled', cancelled_at: Time.current, cancelled_by: actor, cancelled_via: via,
                   cancellation_reason: reason, offer_held_until: nil)
      after_cancel(rsvp, actor, via, reopen)
      result(true, :cancelled, rsvp)
    end
  end

  def promote!(rsvp, actor:)
    occurrence.with_lock do
      rsvp.reload
      return result(false, :invalid, rsvp) unless rsvp.waitlisted?
      return result(false, :full, rsvp) unless occurrence.spots_taken(except: rsvp) < capacity_or_infinity

      mark_confirmed(rsvp)
      journal(actor, 'rsvp_promoted', rsvp)
      result(true, :confirmed, rsvp)
    end
  end

  def check_in!(rsvp, actor:, attended:)
    return result(false, :closed, rsvp) unless occurrence.checkin_open?
    return result(false, :invalid, rsvp) unless rsvp.confirmed?

    if attended
      rsvp.update!(attended: true, checked_in_at: Time.current, checked_in_by: actor)
      journal(actor, 'rsvp_checked_in', rsvp)
    else
      rsvp.update!(attended: nil, checked_in_at: nil, checked_in_by: nil)
    end
    result(true, :checked_in, rsvp)
  end

  def cancel_remaining!(reason: nil)
    reason = reason.presence || occurrence.cancellation_reason
    locked = EventOccurrence.unscoped.find(occurrence.id)
    locked.with_lock do
      locked.rsvps.where.not(status: 'cancelled').find_each do |rsvp|
        rsvp.update!(status: 'cancelled', cancelled_at: Time.current, cancelled_via: 'occurrence_cancelled',
                     cancellation_reason: reason, offer_held_until: nil)
        RsvpNotifier.occurrence_changed(rsvp, 'cancelled')
      end
    end
  end

  def transfer_to!(new_occurrence)
    rows = []
    occurrence.with_lock do
      new_occurrence.with_lock do
        rows = occurrence.rsvps.where.not(status: 'cancelled').to_a
        rows.each { |rsvp| rsvp.update!(event_occurrence: new_occurrence, offer_held_until: nil) }
      end
    end
    rows.each { |rsvp| RsvpNotifier.occurrence_changed(rsvp.reload, 'rescheduled') }
    RsvpAllocator.new(new_occurrence).fill_open_spots
  end

  def notify_change!(kind)
    occurrence.rsvps.where.not(status: 'cancelled').find_each do |rsvp|
      RsvpNotifier.occurrence_changed(rsvp, kind)
    end
  end

  private

  attr_reader :occurrence

  def host_user?(user)
    user.present? && EventHost.exists?(event_id: occurrence.event_id, user_id: user.id)
  end
end
