require 'rails_helper'

RSpec.describe RsvpLifecycle, :mail do
  let(:event) { create(:event, :rsvp, start_time: 5.days.from_now, capacity: 2) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:service) { RsvpService.new(occurrence) }

  before do
    SiteConfig.current
    service.create(user: create(:user, username: 'ada'))
  end

  it 'cancels RSVPs and tells people when the occurrence is cancelled' do
    expect { occurrence.cancel!('Weather', event.user) }.to have_enqueued_mail(RsvpMailer, :occurrence_changed)

    expect(occurrence.rsvps.first.reload.cancelled_via).to eq('occurrence_cancelled')
  end

  it 'moves RSVPs onto the postponed occurrence' do
    original = occurrence.rsvps.first

    expect(occurrence.postpone!(10.days.from_now, 'Room', event.user)).to be true

    moved = original.reload
    expect(moved.event_occurrence).not_to eq(occurrence)
    expect(moved.event_occurrence.occurs_at).to be_within(1.minute).of(10.days.from_now)
    expect(moved).to be_confirmed
  end

  it 'tells people when the occurrence is relocated' do
    expect { occurrence.relocate!('The shop next door', nil, event.user) }
      .to have_enqueued_mail(RsvpMailer, :occurrence_changed)
  end

  it 'tells the wait list when capacity goes up and removes nobody when it goes down' do
    event.update!(capacity: 1)
    waiting = service.create(user: create(:user)).rsvp
    clear_enqueued_jobs

    event.update!(capacity: 2)
    expect { described_class.event_settings_changed!(event) }.to have_enqueued_mail(RsvpMailer, :spot_open)

    expect(waiting.reload).to be_waitlisted
    expect(waiting.last_offered_at).to be_present
    expect(occurrence.rsvps.confirmed.count).to eq(1)
  end

  it 'warns when confirmed RSVPs exceed the new capacity' do
    service.create(user: create(:user))
    event.update!(capacity: 1)

    expect(described_class.over_capacity_warning(event)).to include('Nobody was removed')
    expect(occurrence.rsvps.confirmed.count).to eq(2)
  end

  describe 'cleanup' do
    it 'deletes pending RSVPs that were never confirmed' do
      pending = service.create(name: 'Grace', email: 'grace@example.com').rsvp
      pending.update!(created_at: 25.hours.ago)

      described_class.purge_pending!

      expect(Rsvp.where(id: pending.id)).to be_empty
    end

    it 'marks no-shows only after someone was checked in' do
      rsvp = occurrence.rsvps.confirmed.first
      occurrence.update!(occurs_at: 2.days.ago)

      described_class.finalize_checkins!
      expect(rsvp.reload.attended).to be_nil

      rsvp.update!(attended: true)
      other = service.create(user: create(:user), manual: true).rsvp
      described_class.finalize_checkins!

      expect(other.reload.attended).to be false
      expect(other.user.recent_no_show_count).to eq(1)
      expect(occurrence.reload.checkin_finalized_at).to be_present
    end

    it 'anonymizes guest details after the retention period and keeps member RSVPs' do
      guest = service.create(name: 'Grace', email: 'grace@example.com', manual: true).rsvp
      occurrence.update!(occurs_at: 40.days.ago)
      SiteConfig.current.update!(rsvp_guest_retention_days: 30)

      described_class.anonymize_guests!

      expect(guest.reload.email).to be_nil
      expect(guest.name).to be_nil
      expect(guest.anonymized_at).to be_present
      expect(occurrence.rsvps.where.not(user_id: nil).first.email).to be_present
    end
  end
end
