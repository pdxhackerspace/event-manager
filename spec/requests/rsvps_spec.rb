require 'rails_helper'

RSpec.describe 'RSVPs', :mail, type: :request do
  let(:host) { create(:user, :can_create_events, username: 'hosty') }
  let(:event) { create(:event, :rsvp, user: host, start_time: 4.days.from_now, open_to: 'public') }
  let(:occurrence) { event.occurrences.order(:occurs_at).first }
  let(:member) { create(:user, username: 'ada', name: 'Ada Lovelace') }

  before { SiteConfig.current }

  describe 'finding the RSVP form' do
    it 'shows the form, that an RSVP is required, and how many spots are left on the event page' do
      get event_path(event)

      expect(response.body).to include('RSVP required')
      expect(response.body).to include('2 of 2 spots left')
      expect(response.body).to include('0 taken')
      expect(response.body).to include('2 total')
      expect(response.body).to include('name="name"')
      expect(response.body).to include('name="email"')
      expect(response.body).to include(occurrence_rsvp_path(occurrence))
    end

    it 'shows the same form on the date page, ahead of the other details' do
      get event_occurrence_path(occurrence)

      expect(response.body.index('RSVP required')).to be < response.body.index('Occurrence Details')
      expect(response.body).to include('2 of 2 spots left')
      expect(response.body).to include('name="name"')
    end

    it 'marks the event on the public list' do
      event

      get events_path

      expect(response.body).to include(event.title)
      expect(response.body).to include('RSVP required')
      expect(response.body).to include('2 of 2 spots left')
    end

    it 'asks a guest to log in when the event is members only' do
      event.update!(open_to: 'members')

      get event_path(event)

      expect(response.body).to include('Log in to RSVP')
      expect(response.body).to include("rsvp_occurrence_id=#{occurrence.id}")
      expect(response.body).not_to include('name="email"')
    end

    it 'gives a signed-in member a one-click RSVP on the event page' do
      sign_in member

      get event_path(event)

      expect(response.body).to include('RSVP required')
      expect(response.body).to include(occurrence_rsvp_path(occurrence))
      expect(response.body).not_to include('name="email"')
    end
  end

  describe 'logging in to RSVP' do
    it 'returns to the event and submits the RSVP' do
      get new_user_session_path(rsvp_occurrence_id: occurrence.id, return_to: event_path(event, anchor: 'rsvp'))

      post user_session_path, params: { user: { email: member.email, password: 'password123' } }

      expect(response).to redirect_to(event_path(event, anchor: 'rsvp'))
      expect(flash[:notice]).to include('confirmed')
      follow_redirect!
      expect(response.body).to include('You are confirmed')
      expect(occurrence.rsvps.find_by(user: member)).to be_confirmed
    end

    it 'does not return to an earlier event when the new login has no safe return path' do
      other = create(:event, :rsvp, user: host, start_time: 6.days.from_now, open_to: 'public')
      other_occurrence = other.occurrences.order(:occurs_at).first

      get new_user_session_path(rsvp_occurrence_id: occurrence.id, return_to: event_path(event, anchor: 'rsvp'))
      get new_user_session_path(rsvp_occurrence_id: other_occurrence.id, return_to: 'https://evil.example/phish')

      post user_session_path, params: { user: { email: member.email, password: 'password123' } }

      expect(response).to redirect_to(event_path(other, anchor: 'rsvp'))
      expect(other_occurrence.rsvps.find_by(user: member)).to be_confirmed
      expect(occurrence.rsvps).to be_empty
    end

    it 'does not submit an RSVP from the ordinary sign-in page' do
      get new_user_session_path(rsvp_occurrence_id: occurrence.id, return_to: event_path(event, anchor: 'rsvp'))
      get new_user_session_path

      post user_session_path, params: { user: { email: member.email, password: 'password123' } }

      expect(Rsvp.count).to eq(0)
      expect(response).not_to redirect_to(event_path(event, anchor: 'rsvp'))
    end
  end

  describe 'POST /occurrences/:id/rsvp' do
    it 'confirms a signed-in member' do
      sign_in member

      post occurrence_rsvp_path(occurrence)

      expect(response).to redirect_to(event_occurrence_path(occurrence))
      expect(flash[:notice]).to include('confirmed')
      follow_redirect!
      expect(response.body).to include('You are confirmed')
      expect(response.body).not_to include(member.email)
    end

    it 'uses the same message for a new guest and a guest who already has an account' do
      post occurrence_rsvp_path(occurrence), params: { name: 'Grace', email: 'grace@example.com' }
      guest_notice = flash[:notice]

      post occurrence_rsvp_path(occurrence), params: { name: 'Ada', email: member.email }

      expect(flash[:notice]).to eq(guest_notice)
      expect(occurrence.rsvps.where(email: member.email.downcase)).to be_empty
      expect(occurrence.rsvps.find_by(email: 'grace@example.com')).to be_pending
    end

    it 'ignores a filled-in honeypot' do
      expect do
        post occurrence_rsvp_path(occurrence), params: { name: 'Bot', email: 'bot@example.com', company_website: 'spam' }
      end.not_to change(Rsvp, :count)
    end

    it 'requires login for members-only events' do
      event.update!(open_to: 'members', visibility: 'members')

      post occurrence_rsvp_path(occurrence), params: { name: 'Grace', email: 'grace@example.com' }

      expect(response).to redirect_to(
        new_user_session_path(rsvp_occurrence_id: occurrence.id, return_to: event_path(event, anchor: 'rsvp'))
      )
      expect(Rsvp.count).to eq(0)
    end
  end

  describe 'managing an RSVP from the email link' do
    it 'confirms a guest, then lets them cancel' do
      post occurrence_rsvp_path(occurrence), params: { name: 'Grace', email: 'grace@example.com' }
      token = occurrence.rsvps.last.manage_token

      post confirm_rsvp_path(token)
      expect(occurrence.rsvps.last.reload).to be_confirmed

      post cancel_rsvp_path(token)
      expect(occurrence.rsvps.last.reload).to be_cancelled
    end

    it 'does not cancel an RSVP after the event has ended' do
      rsvp = create(:rsvp, event_occurrence: occurrence, name: 'Grace', email: 'grace@example.com')
      occurrence.update!(occurs_at: 3.hours.ago)

      post cancel_rsvp_path(rsvp.manage_token)

      expect(rsvp.reload).to be_confirmed
      expect(flash[:alert]).to include('over')
    end

    it 'says the event is over after it ends' do
      rsvp = create(:rsvp, event_occurrence: occurrence, name: 'Grace', email: 'grace@example.com')
      occurrence.update!(occurs_at: 3.hours.ago)

      get manage_rsvp_path(rsvp.manage_token)

      expect(response.body).to include('This event is over')
      expect(response.body).not_to include('Cancel RSVP')
    end
  end

  describe 'host list' do
    let!(:guest) { create(:rsvp, event_occurrence: occurrence, name: 'Grace Hopper', email: 'grace@example.com') }

    it 'shows a host the name and not the email' do
      sign_in host

      get event_occurrence_rsvps_path(occurrence)

      expect(response.body).to include('Grace Hopper')
      expect(response.body).not_to include('grace@example.com')
    end

    it 'shows an admin the email and includes it in the CSV' do
      sign_in create(:user, :admin)

      get export_event_occurrence_rsvps_path(occurrence)

      expect(response.body).to include('grace@example.com')
      expect(response.body).to include('Grace Hopper')
    end

    it 'leaves email out of a host CSV' do
      sign_in host

      get export_event_occurrence_rsvps_path(occurrence)

      expect(response.body).to include('Grace Hopper')
      expect(response.body).not_to include('grace@example.com')
    end

    it 'lets a host cancel someone and notifies them' do
      sign_in host

      expect do
        post cancel_event_occurrence_rsvp_path(occurrence, guest), params: { reason: 'No space' }
      end.to have_enqueued_mail(RsvpMailer, :cancelled_by_host)

      expect(guest.reload).to be_cancelled
    end

    it 'does not let another member open the list' do
      sign_in member

      get event_occurrence_rsvps_path(occurrence)

      expect(response).to redirect_to(event_occurrence_path(occurrence))
    end
  end

  describe 'host notification preference' do
    it 'emails the host only after they opt in' do
      sign_in host
      patch event_event_host_path(event, host), params: { notify_on_rsvp: '1' }
      sign_in member

      expect { post occurrence_rsvp_path(occurrence) }.to have_enqueued_mail(RsvpHostMailer, :rsvp_activity)
    end
  end

  it 'links a guest RSVP to the member when they log in through Authentik' do
    email = 'ada-guest@example.com'
    pending = RsvpService.new(occurrence).create(name: 'Ada Lovelace', email: email).rsvp
    member.update!(email: email, provider: 'authentik', uid: 'ada-1', username: nil)
    auth = OmniAuth::AuthHash.new(
      provider: 'authentik', uid: 'ada-1',
      info: { email: email, name: 'Ada Lovelace', nickname: 'ada' },
      extra: { raw_info: { is_admin: false } }
    )

    User.from_omniauth(auth)

    expect(pending.reload.user).to eq(member)
    expect(member.reload.username).to eq('ada')
    expect(pending).to be_confirmed
  end
end
