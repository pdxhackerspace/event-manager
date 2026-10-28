class RsvpLifecycle
  class << self
    def cancel_occurrence!(occurrence)
      RsvpService.new(occurrence).cancel_remaining!(reason: occurrence.cancellation_reason)
    end

    def cancel_event!(event)
      event.occurrences.not_yet_ended.find_each { |occurrence| cancel_occurrence!(occurrence) }
    end

    def transfer!(old_occurrence, new_occurrence)
      RsvpService.new(old_occurrence).transfer_to!(new_occurrence)
    end

    def notify_changed!(occurrence, kind)
      RsvpService.new(occurrence).notify_change!(kind)
    end

    def event_settings_changed!(event)
      changes = event.previous_changes
      return unless changes['capacity'] || changes['waitlist_mode'] || changes['waitlist_enabled']

      event.occurrences.listable_upcoming.find_each do |occurrence|
        apply_capacity_change(occurrence, changes)
      end
    end

    def occurrence_capacity_changed!(occurrence)
      RsvpAllocator.new(occurrence).fill_open_spots(announce_all: true) if capacity_rose?(occurrence)
    end

    def over_capacity_warning(event)
      over = event.occurrences.listable_upcoming.select { |occurrence| over_capacity?(occurrence) }
      return if over.empty?

      dates = over.map { |occurrence| occurrence.occurs_at.strftime('%b %-d') }.to_sentence
      "Capacity is below the number of confirmed RSVPs on #{dates}. Nobody was removed."
    end

    def purge_pending!(at = Time.current)
      Rsvp.where(status: 'pending').includes(:event_occurrence).find_each do |rsvp|
        deadline = [rsvp.created_at + 24.hours, rsvp.event_occurrence.occurs_at].min
        rsvp.destroy if at >= deadline
      end
    end

    def finalize_checkins!(at = Time.current)
      EventOccurrence.where(checkin_finalized_at: nil).where(occurs_at: ..at).find_each do |occurrence|
        next if occurrence.ends_at + 12.hours > at
        next unless occurrence.rsvps.exists?(attended: true)

        occurrence.rsvps.confirmed.where(attended: nil).find_each { |rsvp| rsvp.update!(attended: false) }
        occurrence.update!(checkin_finalized_at: at)
      end
    end

    def anonymize_guests!(at = Time.current)
      days = SiteConfig.current.rsvp_guest_retention_days.to_i
      Rsvp.guests.where(anonymized_at: nil).includes(:event_occurrence).find_each do |rsvp|
        next if rsvp.event_occurrence.ends_at + days.days > at

        rsvp.update!(name: nil, email: nil, anonymized_at: at)
      end
    end

    private

    def apply_capacity_change(occurrence, changes)
      allocator = RsvpAllocator.new(occurrence)
      if changes['waitlist_mode'] || changes['waitlist_enabled']
        allocator.release_all_holds
        allocator.fill_open_spots(announce_all: true)
      elsif capacity_rose_values?(changes['capacity'])
        allocator.fill_open_spots(announce_all: true)
      end
    end

    def capacity_rose?(occurrence)
      return false unless occurrence.saved_change_to_capacity_override?

      capacity_rose_values?(occurrence.saved_change_to_capacity_override)
    end

    def capacity_rose_values?(change)
      return false if change.blank?

      old_cap, new_cap = change
      return true if new_cap.nil? && old_cap.present?
      return false if old_cap.nil?

      new_cap.to_i > old_cap.to_i
    end

    def over_capacity?(occurrence)
      cap = occurrence.effective_capacity
      cap.present? && occurrence.rsvps.confirmed.count > cap
    end
  end
end
