class RsvpService
  module Seating
    private

    def create_member(user)
      rsvp = build_rsvp(user:, name: member_name(user), email: user.email)
      return result(false, :full, rsvp) unless seat_available?

      rsvp.save!
      assign_seat!(rsvp)
    end

    def create_guest(name, email, manual:)
      rsvp = build_rsvp(name:, email:)
      return result(false, :invalid, rsvp) unless rsvp.valid?
      return result(false, :full) unless seat_available?

      rsvp.save!
      return pending_guest(rsvp) unless manual

      outcome = assign_seat!(rsvp)
      rsvp.destroy unless outcome.ok?
      outcome
    end

    def pending_guest(rsvp)
      RsvpNotifier.confirm_email(rsvp)
      result(true, :pending, rsvp)
    end

    def build_rsvp(user: nil, name: nil, email: nil)
      occurrence.rsvps.new(user:, name:, email:, status: 'pending')
    end

    def assign_seat!(rsvp)
      if room_for?(rsvp)
        mark_confirmed(rsvp)
      elsif waitlist?
        mark_waitlisted(rsvp)
      else
        result(false, :full, rsvp)
      end
    end

    def mark_confirmed(rsvp)
      rsvp.update!(status: 'confirmed', confirmed_at: Time.current, waitlisted_at: nil, offer_held_until: nil)
      RsvpNotifier.confirmed(rsvp)
      RsvpNotifier.host_activity(rsvp, 'confirmed')
      result(true, :confirmed, rsvp)
    end

    def mark_waitlisted(rsvp)
      rsvp.update!(status: 'waitlisted', waitlisted_at: rsvp.waitlisted_at || Time.current, offer_held_until: nil)
      RsvpNotifier.waitlisted(rsvp)
      RsvpNotifier.host_activity(rsvp, 'waitlisted')
      result(true, :waitlisted, rsvp)
    end

    def after_cancel(rsvp, actor, via, reopen)
      if %w[host admin].include?(via)
        RsvpNotifier.cancelled_by_host(rsvp)
        journal(actor, 'rsvp_cancelled', rsvp)
      end
      RsvpNotifier.host_activity(rsvp, 'cancelled') unless via == 'occurrence_cancelled'
      return unless reopen && via != 'occurrence_cancelled'

      RsvpAllocator.new(occurrence).fill_open_spots(announce_all: true)
    end

    def login_required(email)
      RsvpNotifier.login_required(email, occurrence)
      result(false, :login_required)
    end

    def account_exists?(email)
      email.present? && User.exists?(['LOWER(email) = ?', email])
    end

    def active_for(user:, email:)
      scope = occurrence.rsvps.active
      found = scope.find_by(user_id: user.id) if user
      found || (email.present? ? scope.where('LOWER(email) = ?', email.downcase).first : nil)
    end

    def seat_available?
      room_for?(nil) || waitlist?
    end

    def room_for?(rsvp)
      occurrence.spots_taken(except: rsvp) < capacity_or_infinity
    end

    def confirmed_full?
      cap = occurrence.effective_capacity
      cap.present? && occurrence.rsvps.confirmed.count >= cap
    end

    def capacity_or_infinity
      occurrence.effective_capacity || Float::INFINITY
    end

    def waitlist?
      occurrence.event.waitlist_enabled? && occurrence.effective_capacity.present?
    end

    def member_name(user)
      user.name.presence || user.username.presence || 'Member'
    end

    def journal(actor, action, rsvp)
      return unless actor

      EventJournal.log_occurrence_change(occurrence, actor, action, { 'name' => rsvp.display_name })
    end

    def result(success, code, rsvp = nil)
      Result.new(ok: success, code:, rsvp:)
    end
  end
end
