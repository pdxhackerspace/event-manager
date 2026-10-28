class RsvpAllocator
  def initialize(occurrence)
    @occurrence = occurrence
  end

  def fill_open_spots(announce_all: false)
    occurrence.with_lock do
      release_expired_holds
      if occurrence.effective_capacity.nil?
        confirm_waitlist
      elsif first_come?
        announce_open_spots(all: announce_all)
      else
        hold_open_spots
      end
    end
  end

  def release_expired_holds
    occurrence.rsvps.waitlisted.where(offer_held_until: ..Time.current).find_each do |rsvp|
      rsvp.update!(offer_held_until: nil)
    end
  end

  def release_all_holds
    occurrence.rsvps.waitlisted.where.not(offer_held_until: nil).find_each do |rsvp|
      rsvp.update!(offer_held_until: nil)
    end
  end

  private

  attr_reader :occurrence

  def first_come?
    occurrence.effective_waitlist_mode == 'first_come'
  end

  def room?(except: nil)
    cap = occurrence.effective_capacity
    cap.nil? || occurrence.spots_taken(except: except) < cap
  end

  def confirm_waitlist
    occurrence.rsvps.waitlisted.each do |rsvp|
      break unless room?

      mark_confirmed(rsvp)
    end
  end

  def announce_open_spots(all:)
    return unless room?

    scope = occurrence.rsvps.waitlisted
    scope = scope.where(last_offered_at: nil) unless all
    scope.each do |rsvp|
      rsvp.update!(last_offered_at: Time.current)
      RsvpNotifier.spot_open(rsvp)
    end
  end

  def hold_open_spots
    while room?
      rsvp = next_candidate
      break unless rsvp

      rsvp.update!(offer_held_until: offer_deadline, last_offered_at: Time.current)
      RsvpNotifier.spot_held(rsvp)
    end
  end

  def next_candidate
    open = occurrence.rsvps.waitlisted.where('offer_held_until IS NULL OR offer_held_until <= ?', Time.current)
    fresh = open.where(last_offered_at: nil).order(:waitlisted_at, :id).first
    return fresh if fresh

    open.where(last_offered_at: ..1.hour.ago).order(:last_offered_at, :id).first
  end

  def offer_deadline
    remaining = occurrence.occurs_at - Time.current
    return Time.current + remaining if remaining < 1.hour

    length = [SiteConfig.current.rsvp_offer_hours.to_i.hours, remaining / 2].min
    length = 1.hour if length < 1.hour
    Time.current + length
  end

  def mark_confirmed(rsvp)
    rsvp.update!(status: 'confirmed', confirmed_at: Time.current, offer_held_until: nil)
    RsvpNotifier.confirmed(rsvp)
    RsvpNotifier.host_activity(rsvp, 'confirmed')
  end
end
