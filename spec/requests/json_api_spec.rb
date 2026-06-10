require 'rails_helper'

RSpec.describe "JSON API", type: :request do
  describe "GET /events.json" do
    let!(:public_event) { create(:event, visibility: 'public', title: 'Public Event', start_time: 1.week.from_now) }
    let!(:members_event) { create(:event, :members_only, title: 'Members Event', start_time: 2.weeks.from_now) }
    let!(:private_event) { create(:event, :private, title: 'Private Event', start_time: 3.weeks.from_now) }
    let!(:cancelled_event) { create(:event, :cancelled, visibility: 'public', title: 'Cancelled Event') }

    before do
      # Ensure occurrences are created
      [public_event, members_event, private_event, cancelled_event].each(&:generate_occurrences)
    end

    it "returns JSON format" do
      get events_path, headers: { 'Accept' => 'application/json' }
      expect(response.content_type).to include('application/json')
      expect(response).to have_http_status(:success)
    end

    it "returns occurrences ordered chronologically" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      expect(json).to have_key('occurrences')
      dates = json['occurrences'].map { |o| Time.parse(o['occurs_at']) }
      expect(dates).to eq(dates.sort)
    end

    it "returns public events with full details and non-public events as 'Private Event'" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      event_titles = json['occurrences'].map { |o| o['event']['title'] }
      # Public event should show its actual title
      expect(event_titles).to include('Public Event')
      # Non-public events should show as 'Private Event'
      expect(event_titles).to include('Private Event')
      # Should not show the actual titles of non-public events
      expect(event_titles).not_to include('Members Event')
      # Cancelled events should not appear (event is cancelled)
      expect(event_titles).not_to include('Cancelled Event')
    end

    it "includes both members and private events as 'Private Event'" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      # Find occurrences where event title is "Private Event" (both members and private visibility)
      private_occs = json['occurrences'].select { |o| o['event']['title'] == 'Private Event' }
      expect(private_occs.length).to eq(2) # one each for members_event and private_event
    end

    it "hides details for non-public events" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      private_occ = json['occurrences'].find { |o| o['event']['title'] == 'Private Event' }
      expect(private_occ['event']['description']).to be_nil
      expect(private_occ['event']['hosts']).to eq([])
      expect(private_occ['event']['location']).to be_nil
      expect(private_occ['event']['banner_url']).to be_nil
      expect(private_occ['duration']).to be_nil
      expect(private_occ['description']).to be_nil
    end

    it "shows occurrence times for non-public events (for scheduling)" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      private_occ = json['occurrences'].find { |o| o['event']['title'] == 'Private Event' }
      expect(private_occ['occurs_at']).to be_present
    end

    it "excludes occurrences that have already passed" do
      # Create an event with only past occurrences
      past_event = create(:event, visibility: 'public', title: 'Past Event', start_time: 2.weeks.ago)
      past_event.occurrences.destroy_all
      create(:event_occurrence, event: past_event, occurs_at: 1.week.ago)

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      event_titles = json['occurrences'].map { |o| o['event']['title'] }
      expect(event_titles).not_to include('Past Event')
    end

    it "includes occurrences currently in progress" do
      # Create an event that started 30 minutes ago with 2 hour duration (so still in progress)
      in_progress_event = create(:event, visibility: 'public', title: 'In Progress Event', start_time: 30.minutes.ago, duration: 120)
      in_progress_event.occurrences.destroy_all
      create(:event_occurrence, event: in_progress_event, occurs_at: 30.minutes.ago)

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      event_titles = json['occurrences'].map { |o| o['event']['title'] }
      expect(event_titles).to include('In Progress Event')
    end

    it "shows in_progress true for occurrences currently happening" do
      # Create an event that started 30 minutes ago with 2 hour duration (so still in progress)
      in_progress_event = create(:event, visibility: 'public', title: 'In Progress Event', start_time: 30.minutes.ago, duration: 120)
      in_progress_event.occurrences.destroy_all
      create(:event_occurrence, event: in_progress_event, occurs_at: 30.minutes.ago)

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      occ = json['occurrences'].find { |o| o['event']['title'] == 'In Progress Event' }
      expect(occ['in_progress']).to be true
    end

    it "shows in_progress false for future occurrences" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      occ = json['occurrences'].find { |o| o['event']['title'] == 'Public Event' }
      expect(occ['in_progress']).to be false
    end

    it "includes open_to for public events" do
      public_event.update!(open_to: 'members')

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      occ = json['occurrences'].find { |o| o['event']['title'] == 'Public Event' }
      expect(occ['open_to']).to eq('members')
    end

    it "hides open_to for non-public events" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      # Find a private event occurrence (shows as 'Private Event')
      private_occs = json['occurrences'].select { |o| o['event']['title'] == 'Private Event' }
      private_occs.each do |occ|
        expect(occ['open_to']).to be_nil
      end
    end

    it "includes response metadata" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      expect(json).to have_key('events')
      expect(json).to have_key('occurrences')
      expect(json).to have_key('generated_at')
      expect(json).to have_key('event_count')
      expect(json).to have_key('occurrence_count')
    end

    it "includes standard occurrence details" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      return if json['occurrences'].empty?

      occ = json['occurrences'].first
      expect(occ).to have_key('id')
      expect(occ).to have_key('slug')
      expect(occ).to have_key('occurs_at')
      expect(occ).to have_key('duration')
      expect(occ).to have_key('event')
      expect(occ).to have_key('location')
      expect(occ).to have_key('description')
    end

    it "includes status and progress flags" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      return if json['occurrences'].empty?

      occ = json['occurrences'].first
      expect(occ).to have_key('is_cancelled')
      expect(occ).to have_key('is_postponed')
      expect(occ).to have_key('in_progress')
      expect(occ).to have_key('open_to')
    end

    it "includes event info for each occurrence" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      return if json['occurrences'].empty?

      event_info = json['occurrences'].first['event']
      expect(event_info).to have_key('id')
      expect(event_info).to have_key('slug')
      expect(event_info).to have_key('title')
      expect(event_info).to have_key('description')
      expect(event_info).to have_key('hosts')
      expect(event_info).to have_key('location')
    end

    it "includes hosts as simple array of names" do
      user = create(:user, name: 'John Doe')
      event = create(:event, visibility: 'public', user: user)

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ = json['occurrences'].find { |o| o['event']['id'] == event.id }

      expect(occ['event']['hosts']).to be_an(Array)
      expect(occ['event']['hosts']).to include('John Doe')
      expect(occ['event']['hosts'].to_s).not_to include('@')
    end

    it "includes banner URLs when present" do
      event_with_banner = create(:event, :with_banner, visibility: 'public')

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ = json['occurrences'].find { |o| o['event']['id'] == event_with_banner.id }

      expect(occ['event']['banner_url']).to be_present
      expect(occ['event']['banner_url']).to include('rails/active_storage')
    end

    it "sets banner_url to null when no banner" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ = json['occurrences'].find { |o| o['event']['id'] == public_event.id }

      expect(occ['event']['banner_url']).to be_nil
    end

    it "shows is_cancelled true for cancelled occurrences" do
      public_event.occurrences.first.update!(status: 'cancelled')

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ = json['occurrences'].find { |o| o['event']['id'] == public_event.id }

      expect(occ['is_cancelled']).to be true
      expect(occ['is_postponed']).to be false
    end

    it "shows is_postponed true for postponed occurrences" do
      public_event.occurrences.first.update!(status: 'postponed', postponed_until: 2.weeks.from_now)

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ = json['occurrences'].find { |o| o['event']['id'] == public_event.id }

      expect(occ['is_postponed']).to be true
      expect(occ['is_cancelled']).to be false
      expect(occ['postponed_until']).to be_present
    end

    it "includes weekday and month abbreviations for each occurrence" do
      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      return if json['occurrences'].empty?

      occ = json['occurrences'].first
      expect(occ).to have_key('weekday_abbr')
      expect(occ).to have_key('month_abbr')
      expect(occ['weekday_abbr']).to match(/\A[A-Z][a-z]{2}\z/)
      expect(occ['month_abbr']).to match(/\A[A-Z][a-z]{2}\z/)
    end

    it "includes occurrences in progress when duration_override extends end time" do
      in_progress_event = create(
        :event,
        visibility: 'public',
        title: 'Extended Event',
        start_time: 30.minutes.ago,
        duration: 30
      )
      in_progress_event.occurrences.destroy_all
      create(:event_occurrence, :with_duration_override, event: in_progress_event, occurs_at: 30.minutes.ago)

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      event_titles = json['occurrences'].map { |o| o['event']['title'] }
      expect(event_titles).to include('Extended Event')
    end

    it "includes in-progress occurrences using app timezone wall clock" do
      now = Time.zone.local(2026, 6, 10, 19, 30, 0)
      start = Time.zone.local(2026, 6, 10, 18, 0, 0)

      Time.use_zone('America/Los_Angeles') do
        allow(Time).to receive(:current).and_return(now)
        in_progress_event = create(:event, visibility: 'public', title: 'Tonight Event', start_time: start, duration: 180)
        in_progress_event.occurrences.destroy_all
        create(:event_occurrence, event: in_progress_event, occurs_at: start)

        get events_path, headers: { 'Accept' => 'application/json' }
        occ = JSON.parse(response.body)['occurrences'].find { |o| o['event']['title'] == 'Tonight Event' }

        expect(occ).to include('in_progress' => true, 'weekday_abbr' => 'Wed', 'month_abbr' => 'Jun')
      end
    end

    it "does not require authentication" do
      get events_path, headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /calendar.json" do
    let!(:public_event) { create(:event, visibility: 'public', title: 'Public Event') }
    let!(:members_event) { create(:event, :members_only, title: 'Members Event') }
    let!(:private_event) { create(:event, :private, title: 'Private Event') }

    before do
      # Create some occurrences
      create(:event_occurrence, event: public_event, occurs_at: 1.week.from_now)
      create(:event_occurrence, event: public_event, occurs_at: 2.weeks.from_now)
      create(:event_occurrence, event: members_event, occurs_at: 1.week.from_now)
      create(:event_occurrence, event: private_event, occurs_at: 1.week.from_now)
    end

    it "returns JSON format" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      expect(response.content_type).to include('application/json')
      expect(response).to have_http_status(:success)
    end

    it "returns only public event occurrences" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      event_titles = json['occurrences'].map { |o| o['event']['title'] }
      expect(event_titles).to include('Public Event')
      expect(event_titles).not_to include('Members Event', 'Private Event')
    end

    it "does not include grouped_by_month" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      expect(json).not_to have_key('grouped_by_month')
    end

    it "includes occurrence metadata" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      expect(json).to have_key('occurrences')
      expect(json).to have_key('generated_at')
      expect(json).to have_key('count')
    end

    it "includes occurrence details" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      return if json['occurrences'].empty?

      occurrence = json['occurrences'].first
      expect(occurrence).to have_key('id')
      expect(occurrence).to have_key('occurs_at')
      expect(occurrence).to have_key('status')
      expect(occurrence).to have_key('duration')
      expect(occurrence).to have_key('description')
      expect(occurrence).to have_key('in_progress')
      expect(occurrence).to have_key('open_to')
      expect(occurrence).to have_key('event')
    end

    it "includes event information for each occurrence" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      return if json['occurrences'].empty?

      occurrence = json['occurrences'].first
      event = occurrence['event']

      expect(event).to have_key('id')
      expect(event).to have_key('title')
      expect(event).to have_key('hosts')
      expect(event).to have_key('visibility')
      expect(event).to have_key('open_to')
    end

    it "includes hosts as simple array without emails" do
      user = create(:user, name: 'Jane Doe')
      event = create(:event, visibility: 'public', user: user)
      create(:event_occurrence, event: event, occurs_at: 1.week.from_now)

      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occurrence = json['occurrences'].find { |o| o['event']['id'] == event.id }

      expect(occurrence['event']['hosts']).to be_an(Array)
      expect(occurrence['event']['hosts']).to include('Jane Doe')
      # Ensure no email addresses
      expect(occurrence['event']['hosts'].to_s).not_to include('@')
    end

    it "sorts occurrences by date (earliest first)" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      return if json['occurrences'].length < 2

      dates = json['occurrences'].map { |o| Time.parse(o['occurs_at']) }
      expect(dates).to eq(dates.sort)
    end

    it "includes postponed occurrence details" do
      postponed_occurrence = create(:event_occurrence, :postponed, event: public_event, occurs_at: 3.weeks.from_now)

      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ_json = json['occurrences'].find { |o| o['id'] == postponed_occurrence.id }

      expect(occ_json['status']).to eq('postponed')
      expect(occ_json['postponed_until']).to be_present
      expect(occ_json['cancellation_reason']).to be_present
    end

    it "includes cancelled occurrence details" do
      cancelled_occurrence = create(:event_occurrence, :cancelled, event: public_event, occurs_at: 4.weeks.from_now)

      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ_json = json['occurrences'].find { |o| o['id'] == cancelled_occurrence.id }

      expect(occ_json['status']).to eq('cancelled')
      expect(occ_json['cancellation_reason']).to be_present
    end

    it "includes banner URLs" do
      event_with_banner = create(:event, :with_banner, visibility: 'public')
      occ_with_banner = create(:event_occurrence, event: event_with_banner, occurs_at: 5.weeks.from_now)

      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ_json = json['occurrences'].find { |o| o['id'] == occ_with_banner.id }

      expect(occ_json['banner_url']).to be_present
    end

    it "indicates when occurrence has custom banner" do
      event = create(:event, :with_banner, visibility: 'public')
      occ_with_custom = create(:event_occurrence, :with_banner, event: event, occurs_at: 6.weeks.from_now)

      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)
      occ_json = json['occurrences'].find { |o| o['id'] == occ_with_custom.id }

      expect(occ_json['has_custom_banner']).to be true
    end

    it "does not require authentication" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:success)
    end

    it "shows in_progress true for occurrences currently happening" do
      # Create an event that started 30 minutes ago with 2 hour duration (so still in progress)
      in_progress_event = create(:event, visibility: 'public', title: 'In Progress Event', start_time: 30.minutes.ago, duration: 120)
      in_progress_event.occurrences.destroy_all
      create(:event_occurrence, event: in_progress_event, occurs_at: 30.minutes.ago)

      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      occ = json['occurrences'].find { |o| o['event']['title'] == 'In Progress Event' }
      expect(occ['in_progress']).to be true
    end

    it "shows in_progress false for future occurrences" do
      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      return if json['occurrences'].empty?

      occ = json['occurrences'].first
      expect(occ['in_progress']).to be false
    end

    it "includes open_to at the occurrence level" do
      public_event.update!(open_to: 'members')

      get calendar_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      occ = json['occurrences'].find { |o| o['event']['id'] == public_event.id }
      expect(occ['open_to']).to eq('members')
    end
  end
end
