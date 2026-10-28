require 'rails_helper'

RSpec.describe RsvpHostMailer, type: :mailer do
  let(:host) { create(:user, name: 'Host Person', email: 'host@example.com') }
  let(:event) { create(:event, :rsvp, user: host, start_time: 4.days.from_now) }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:member) { create(:user, username: 'ada', name: 'Ada Lovelace', email: 'ada@example.com') }
  let(:rsvp) { create(:rsvp, event_occurrence: occurrence, user: member, name: member.name, email: member.email) }

  before { SiteConfig.current }

  it 'shows the username and not the email address' do
    body = described_class.rsvp_activity(host, rsvp, 'confirmed').text_part.body.decoded

    expect(body).to include('ada')
    expect(body).not_to include('ada@example.com')
    expect(body).not_to include('Ada Lovelace')
  end
end
