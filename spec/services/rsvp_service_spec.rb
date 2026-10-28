require 'rails_helper'

RSpec.describe RsvpService, :mail do
  let(:event) { create(:event, :rsvp, start_time: 5.days.from_now, capacity: 1) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:service) { described_class.new(occurrence) }
  let(:member) { create(:user, username: 'ada', name: 'Ada Lovelace', email: 'ada@example.com') }

  before { SiteConfig.current }

  describe '#create' do
    it 'does not let a host RSVP' do
      outcome = service.create(user: event.user)

      expect(outcome.code).to eq(:host)
      expect(Rsvp.count).to eq(0)
    end

    it 'does not let a host be added by email' do
      outcome = service.create(name: 'Host', email: event.user.email, manual: true)

      expect(outcome.code).to eq(:host)
      expect(Rsvp.count).to eq(0)
    end

    it 'still lets an admin who is not a host RSVP' do
      expect(service.create(user: create(:user, :admin)).code).to eq(:confirmed)
    end

    it 'confirms a member and prefers their username' do
      outcome = nil
      expect { outcome = service.create(user: member) }.to have_enqueued_mail(RsvpMailer, :confirmed)

      expect(outcome.code).to eq(:confirmed)
      expect(outcome.rsvp.display_name).to eq('ada')
      expect(outcome.rsvp.email).to eq('ada@example.com')
    end

    it 'waitlists a member when the event is full' do
      service.create(user: member)
      other = create(:user)

      outcome = service.create(user: other)

      expect(outcome.code).to eq(:waitlisted)
      expect(outcome.rsvp.waitlist_position).to eq(1)
    end

    it 'refuses a member when the event is full and there is no wait list' do
      event.update!(waitlist_enabled: false)
      service.create(user: member)

      outcome = service.create(user: create(:user))

      expect(outcome.code).to eq(:full)
      expect(occurrence.rsvps.count).to eq(1)
    end

    it 'starts a guest as pending and does not take a spot' do
      outcome = nil
      expect { outcome = service.create(name: 'Grace', email: 'grace@example.com') }
        .to have_enqueued_mail(RsvpMailer, :confirm_email)

      expect(outcome.code).to eq(:pending)
      expect(occurrence.spots_taken).to eq(0)
    end

    it 'asks a guest who already has an account to log in, without saying whether the account exists' do
      member
      outcome = nil
      expect { outcome = service.create(name: 'Ada', email: member.email.upcase) }
        .to have_enqueued_mail(RsvpMailer, :login_required)

      expect(outcome.code).to eq(:login_required)
      expect(occurrence.rsvps).to be_empty
    end

    it 'rejects a second RSVP for the same email' do
      service.create(name: 'Grace', email: 'grace@example.com')

      outcome = service.create(name: 'Grace Hopper', email: 'Grace@example.com')

      expect(outcome.code).to eq(:duplicate)
    end

    it 'rejects RSVPs after the cutoff' do
      event.update!(rsvp_closes_minutes_before: 24 * 60 * 6)

      expect(service.create(user: member).code).to eq(:closed)
    end

    it 'lets only one of two simultaneous members take the last seat', :concurrency do
      ids = create_list(:user, 2).map(&:id)
      results = Queue.new
      threads = ids.map do |user_id|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            occ = EventOccurrence.find(occurrence.id)
            results << described_class.new(occ).create(user: User.find(user_id)).code
          end
        rescue StandardError => e
          results << e
        end
      end
      threads.each(&:join)
      codes = Array.new(ids.size) { results.pop }

      expect(codes).to contain_exactly(:confirmed, :waitlisted)
    end
  end

  describe '#confirm_pending!' do
    it 'gives the guest the spot after they confirm' do
      created = service.create(name: 'Grace', email: 'grace@example.com')

      outcome = service.confirm_pending!(created.rsvp)

      expect(outcome.code).to eq(:confirmed)
      expect(occurrence.reload.spots_taken).to eq(1)
    end

    it 'waitlists the guest when the spot was taken' do
      created = service.create(name: 'Grace', email: 'grace@example.com')
      service.create(user: member)

      expect(service.confirm_pending!(created.rsvp).code).to eq(:waitlisted)
    end
  end

  describe '#cancel!' do
    it 'emails the wait list that a spot opened' do
      service.create(user: member)
      waiting = service.create(user: create(:user))
      clear_enqueued_jobs

      expect { service.cancel!(occurrence.rsvps.confirmed.first, via: 'self') }
        .to have_enqueued_mail(RsvpMailer, :spot_open).with(waiting.rsvp)
    end

    it 'emails the person when a host cancels them and records the journal' do
      service.create(user: member)
      rsvp = occurrence.rsvps.confirmed.first

      expect { service.cancel!(rsvp, actor: event.user, via: 'host', reason: 'Duplicate') }
        .to have_enqueued_mail(RsvpMailer, :cancelled_by_host)

      expect(EventJournal.where(action: 'rsvp_cancelled').last.change_data['name']).to eq('ada')
      expect(rsvp.reload.cancellation_reason).to eq('Duplicate')
    end
  end

  describe 'wait list modes' do
    it 'holds the spot for the next person in sequential mode' do
      event.update!(waitlist_mode: 'sequential', capacity: 1)
      service.create(user: member)
      waiting = service.create(user: create(:user, username: 'grace'))
      clear_enqueued_jobs

      service.cancel!(occurrence.rsvps.confirmed.first, via: 'self')

      held = waiting.rsvp.reload
      expect(held.offer_held_until).to be > Time.current
      expect(held.holding_offer?).to be true
      expect(service.claim!(held).code).to eq(:confirmed)
    end

    it 'keeps someone on the wait list when their hold expires and offers the next person' do
      event.update!(waitlist_mode: 'sequential', capacity: 1)
      service.create(user: member)
      first = service.create(user: create(:user)).rsvp
      second = service.create(user: create(:user)).rsvp
      service.cancel!(occurrence.rsvps.confirmed.first, via: 'self')
      first.update!(offer_held_until: 1.minute.ago)

      RsvpAllocator.new(occurrence).fill_open_spots

      expect(first.reload).to be_waitlisted
      expect(first.offer_held_until).to be_nil
      expect(second.reload.holding_offer?).to be true
    end

    it 'switches to first come, first served inside the last-call window' do
      event.update!(waitlist_mode: 'sequential', capacity: 1, start_time: 2.hours.from_now)
      occurrence.update!(occurs_at: 2.hours.from_now)
      SiteConfig.current.update!(rsvp_last_call_hours: 4)
      service.create(user: member)
      waiting = service.create(user: create(:user)).rsvp

      service.cancel!(occurrence.rsvps.confirmed.first, via: 'self')

      expect(waiting.reload.offer_held_until).to be_nil
      expect(waiting.last_offered_at).to be_present
      expect(service.claim!(waiting).code).to eq(:confirmed)
    end

    it 'leaves the first person waiting when a later person claims the open spot' do
      service.create(user: member)
      first = service.create(user: create(:user)).rsvp
      second = service.create(user: create(:user)).rsvp
      service.cancel!(occurrence.rsvps.confirmed.first, via: 'self')

      expect(service.claim!(second).code).to eq(:confirmed)
      expect(service.claim!(first.reload).code).to eq(:taken)
      expect(first.reload).to be_waitlisted
    end
  end

  describe '#promote! and #check_in!' do
    it 'promotes a waitlisted person into an open spot' do
      service.create(user: member)
      waiting = service.create(user: create(:user, username: 'grace')).rsvp
      service.cancel!(occurrence.rsvps.confirmed.first, via: 'self')
      waiting.reload

      outcome = service.promote!(waiting, actor: event.user)

      expect(outcome.code).to eq(:confirmed)
      expect(EventJournal.where(action: 'rsvp_promoted').last.change_data['name']).to eq('grace')
    end

    it 'checks a confirmed person in during the event' do
      service.create(user: member)
      occurrence.update!(occurs_at: 30.minutes.ago)
      rsvp = occurrence.rsvps.confirmed.first

      expect(service.check_in!(rsvp, actor: event.user, attended: true).code).to eq(:checked_in)
      expect(rsvp.reload.attended).to be true
      expect(event.user.recent_no_show_count).to eq(0)
    end
  end

  describe 'manual add' do
    it 'confirms a guest immediately' do
      outcome = service.create(name: 'Walk in', email: 'walkin@example.com', manual: true)

      expect(outcome.code).to eq(:confirmed)
      expect(outcome.rsvp.user).to be_nil
    end

    it 'links an existing account instead of asking them to log in' do
      outcome = service.create(name: 'Ada', email: member.email, manual: true)

      expect(outcome.code).to eq(:confirmed)
      expect(outcome.rsvp.user).to eq(member)
      expect(outcome.rsvp.display_name).to eq('ada')
    end
  end
end
