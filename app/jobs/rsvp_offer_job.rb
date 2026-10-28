class RsvpOfferJob < ApplicationJob
  queue_as :mailers

  def perform
    occurrence_ids = Rsvp.where(status: 'waitlisted').distinct.pluck(:event_occurrence_id)
    EventOccurrence.where(id: occurrence_ids).find_each do |occurrence|
      RsvpAllocator.new(occurrence).fill_open_spots
      send_offer_reminders(occurrence)
    end
  end

  private

  def send_offer_reminders(occurrence)
    return unless occurrence.spots_remaining.nil? || occurrence.spots_remaining.positive? || occurrence.rsvps.waitlisted.any?(&:holding_offer?)

    occurrence.rsvps.waitlisted.where(offer_reminder_sent_at: nil).where.not(last_offered_at: nil).find_each do |rsvp|
      next unless reminder_due?(rsvp)
      next unless spot_still_open?(occurrence, rsvp)

      RsvpNotifier.offer_reminder(rsvp)
      rsvp.update!(offer_reminder_sent_at: Time.current)
    end
  end

  def reminder_due?(rsvp)
    Time.current >= reminder_at(rsvp)
  end

  def reminder_at(rsvp)
    if rsvp.offer_held_until.present? && rsvp.offer_held_until > rsvp.last_offered_at
      rsvp.last_offered_at + ((rsvp.offer_held_until - rsvp.last_offered_at) / 2)
    else
      rsvp.last_offered_at + 12.hours
    end
  end

  def spot_still_open?(occurrence, rsvp)
    rsvp.holding_offer? || occurrence.spots_remaining.nil? || occurrence.spots_remaining.positive?
  end
end
