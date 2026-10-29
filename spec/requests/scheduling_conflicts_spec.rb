require 'rails_helper'

RSpec.describe 'Scheduling conflicts', :mail, type: :request do
  let(:host) { create(:user, :can_create_events) }
  let(:admin) { create(:user, :admin) }
  let(:start_time) { Time.zone.parse('2026-11-14 18:00') }
  let!(:exclusive) do
    create(:event, title: 'Fundraiser', user: admin, start_time: start_time, duration: 120,
                   exclusive_status: 'approved', conflict_buffer_minutes: 60)
  end

  def event_params(overrides = {})
    {
      event: {
        title: 'Workshop',
        description: 'Hands on',
        start_time: start_time,
        duration: 60,
        recurrence_type: 'once',
        visibility: 'public',
        open_to: 'public'
      }.merge(overrides)
    }
  end

  describe 'creating an event' do
    before { sign_in host }

    it 'refuses a time that overlaps an exclusive event' do
      expect do
        post events_path, params: event_params
      end.not_to change(Event, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Fundraiser')
      expect(response.body).to include('Please choose a different time')
    end

    it 'saves a busy overlap and cautions afterwards' do
      exclusive.update!(exclusive_status: 'none', busy: true)

      post events_path, params: event_params

      expect(response).to redirect_to(Event.find_by(title: 'Workshop'))
      expect(flash[:busy_conflict]).to include('very busy')
    end

    it 'does not let a host override an exclusive block' do
      expect do
        post events_path, params: event_params.merge(override_exclusive_conflict: '1')
      end.not_to change(Event, :count)
    end
  end

  describe 'an admin override' do
    before { sign_in admin }

    it 'saves over an exclusive event and records who did it' do
      expect do
        post events_path, params: event_params.merge(override_exclusive_conflict: '1')
      end.to change(Event, :count).by(1)

      created = Event.find_by(title: 'Workshop')
      journal = created.event_journals.find_by(action: 'exclusive_override')
      expect(journal.change_data['overlapped']).to include('Fundraiser')
    end
  end

  describe 'the live check' do
    before { sign_in host }

    it 'reports an exclusive block for the time being entered' do
      get conflict_check_events_path, params: event_params

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-exclusive-block')
      expect(response.body).to include('Fundraiser')
    end
  end

  describe 'occurrence changes' do
    let(:event) { create(:event, user: host, start_time: start_time + 1.day, duration: 60) }
    let(:occurrence) { event.occurrences.first }

    before { sign_in host }

    it 'refuses moving an occurrence into an exclusive window' do
      patch event_occurrence_path(occurrence), params: {
        event_occurrence: { occurs_at: start_time.strftime('%Y-%m-%dT%H:%M') }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(occurrence.reload.occurs_at).to be_within(1.minute).of(event.start_time)
    end

    it 'refuses reactivating a cancelled date inside an exclusive window' do
      overlapping = build(:event, user: host, start_time: start_time, duration: 60)
      overlapping.save!(validate: false)
      cancelled = overlapping.occurrences.first
      cancelled.update!(status: 'cancelled', cancellation_reason: 'Called off')

      post reactivate_event_occurrence_path(cancelled)

      expect(response).to redirect_to(event_occurrence_path(cancelled))
      expect(flash[:alert]).to include('Fundraiser')
      expect(cancelled.reload.status).to eq('cancelled')
    end

    it 'refuses postponing into an exclusive window' do
      post postpone_event_occurrence_path(occurrence), params: { postponed_until: start_time.strftime('%Y-%m-%dT%H:%M') }

      expect(response).to redirect_to(event_occurrence_path(occurrence))
      expect(flash[:alert]).to include('Fundraiser')
      expect(occurrence.reload.status).to eq('active')
    end
  end
end
