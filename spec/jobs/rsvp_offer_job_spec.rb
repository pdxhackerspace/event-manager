require 'rails_helper'

RSpec.describe RsvpOfferJob, :mail, type: :job do
  let(:event) { create(:event, :rsvp, start_time: 3.days.from_now, capacity: 1, waitlist_mode: 'first_come') }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }

  before { SiteConfig.current }

  it 'sends one offer reminder while a spot is still open' do
    service = RsvpService.new(occurrence)
    service.create(user: create(:user))
    waiting = service.create(user: create(:user)).rsvp
    service.cancel!(occurrence.rsvps.confirmed.first, via: 'self')
    waiting.update!(last_offered_at: 13.hours.ago, offer_reminder_sent_at: nil)
    clear_enqueued_jobs

    expect { described_class.perform_now }.to have_enqueued_mail(RsvpMailer, :offer_reminder)
    expect(waiting.reload.offer_reminder_sent_at).to be_present

    expect { described_class.perform_now }.not_to have_enqueued_mail(RsvpMailer, :offer_reminder)
  end

  it 'does not remind anyone when the spot has been filled' do
    service = RsvpService.new(occurrence)
    service.create(user: create(:user))
    waiting = service.create(user: create(:user)).rsvp
    waiting.update!(last_offered_at: 13.hours.ago)
    clear_enqueued_jobs

    expect { described_class.perform_now }.not_to have_enqueued_mail(RsvpMailer, :offer_reminder)
  end
end
