require 'rails_helper'

RSpec.describe RsvpReminderJob, :mail, type: :job do
  let(:event) { create(:event, :rsvp, start_time: 5.days.from_now, capacity: 1) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:rsvp) { RsvpService.new(occurrence).create(user: create(:user)).rsvp }

  before { SiteConfig.current }

  it 'sends the one-week reminder once' do
    rsvp

    expect { described_class.perform_now }.to have_enqueued_mail(RsvpMailer, :reminder)
    expect(rsvp.reload.reminder_7d_sent_at).to be_present

    expect { described_class.perform_now }.not_to have_enqueued_mail(RsvpMailer, :reminder)
  end

  it 'includes the release nag on the one-day reminder when the event is full' do
    confirmed = rsvp
    RsvpService.new(occurrence).create(user: create(:user))
    occurrence.update!(occurs_at: 12.hours.from_now)
    clear_enqueued_jobs

    expect { described_class.perform_now }.to have_enqueued_mail(RsvpMailer, :reminder)
    expect(confirmed.reload.release_nag_sent_at).to be_present
  end

  it 'skips people who opted out' do
    rsvp.update!(reminders_opted_out: true)

    expect { described_class.perform_now }.not_to have_enqueued_mail(RsvpMailer, :reminder)
  end
end
