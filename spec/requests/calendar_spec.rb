require 'rails_helper'

RSpec.describe "Calendar", type: :request do
  let(:user) { create(:user) }

  describe "GET /calendar" do
    let!(:public_event) { create(:event, visibility: 'public', start_time: 1.week.from_now) }
    let!(:members_event) { create(:event, :members_only, start_time: 2.weeks.from_now) }
    let!(:private_event) { create(:event, :private, start_time: 3.weeks.from_now) }

    context "as a guest" do
      it "returns success" do
        get calendar_path
        expect(response).to have_http_status(:success)
      end

      it "shows public event occurrences only" do
        get calendar_path(view: 'list')
        expect(response.body).to include(public_event.title)
        expect(response.body).not_to include(members_event.title)
        expect(response.body).not_to include(private_event.title)
      end

      it "displays occurrences" do
        get calendar_path
        public_occurrence = public_event.occurrences.first
        # Calendar shows day number without leading zero
        expect(response.body).to include(public_occurrence.occurs_at.day.to_s)
        expect(response.body).to include(public_occurrence.occurs_at.strftime('%B'))
      end
    end

    context "as a logged-in user" do
      before { sign_in user }

      it "shows public and members event occurrences" do
        get calendar_path(view: 'list')
        expect(response.body).to include(public_event.title)
        expect(response.body).to include(members_event.title)
        expect(response.body).not_to include(private_event.title)
      end
    end

    context "as an admin" do
      let(:admin) { create(:user, :admin) }

      before { sign_in admin }

      it "shows all event occurrences" do
        get calendar_path(view: 'list')
        expect(response.body).to include(public_event.title)
        expect(response.body).to include(members_event.title)
        expect(response.body).to include(private_event.title)
      end
    end

    context "with no upcoming events" do
      before do
        Event.destroy_all
      end

      it "shows a message about no events" do
        get calendar_path(view: 'list')
        expect(response.body).to include("No upcoming event occurrences")
      end
    end

    context "view parameter" do
      it "defaults to calendar view" do
        get calendar_path
        expect(response).to have_http_status(:success)
        # Calendar view should have calendar grid elements
        expect(response.body).to include('calendar')
      end

      it "supports list view" do
        get calendar_path(view: 'list')
        expect(response).to have_http_status(:success)
      end
    end

    context "month navigation" do
      it "accepts month parameter" do
        get calendar_path(month: '2025-06-01')
        expect(response).to have_http_status(:success)
        expect(response.body).to include('June')
      end

      it "defaults to current month" do
        get calendar_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(Date.current.strftime('%B'))
      end
    end

    context "open_to filter" do
      let!(:public_open_event) { create(:event, visibility: 'public', open_to: 'public', start_time: 1.week.from_now) }
      let!(:members_open_event) { create(:event, visibility: 'public', open_to: 'members', start_time: 2.weeks.from_now) }

      it "filters by open_to parameter" do
        get calendar_path(view: 'list', open_to: 'public')
        expect(response.body).to include(public_open_event.title)
        expect(response.body).not_to include(members_open_event.title)
      end
    end

    context "JSON format" do
      it "returns JSON response" do
        get calendar_path(format: :json)
        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('application/json')
      end

      it "includes occurrences in JSON" do
        get calendar_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to have_key('occurrences')
        expect(json).to have_key('generated_at')
      end
    end
  end

  describe "GET /calendar/embed" do
    let!(:public_event) { create(:event, visibility: 'public', start_time: 1.week.from_now) }
    let!(:private_event) { create(:event, :private, start_time: 2.weeks.from_now) }

    it "returns success" do
      get calendar_embed_path
      expect(response).to have_http_status(:success)
    end

    it "uses embed layout" do
      get calendar_embed_path
      # Embed layout should not have standard navigation
      expect(response.body).not_to include('Sign in')
    end

    it "shows only public events" do
      get calendar_embed_path(view: 'list')
      expect(response.body).to include(public_event.title)
      expect(response.body).not_to include(private_event.title)
    end

    it "removes X-Frame-Options header" do
      get calendar_embed_path
      expect(response.headers['X-Frame-Options']).to be_nil
    end

    it "supports month parameter" do
      get calendar_embed_path(month: '2025-06-01')
      expect(response).to have_http_status(:success)
    end

    it "supports view parameter" do
      get calendar_embed_path(view: 'list')
      expect(response).to have_http_status(:success)
    end

    it "supports open_to filter" do
      get calendar_embed_path(open_to: 'public')
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /calendar.ics" do
    # rubocop:disable RSpec/LetSetup
    let!(:public_event) { create(:event, visibility: 'public', start_time: 1.week.from_now, title: 'Public iCal Event') }
    let!(:private_event) { create(:event, :private, start_time: 2.weeks.from_now, title: 'Private iCal Event') }
    let!(:draft_event) { create(:event, visibility: 'public', draft: true, start_time: 3.weeks.from_now, title: 'Draft iCal Event') }
    # rubocop:enable RSpec/LetSetup

    it "returns iCal format" do
      get calendar_ical_path(format: :ics)
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('text/calendar')
    end

    it "includes VCALENDAR structure" do
      get calendar_ical_path(format: :ics)
      expect(response.body).to include('BEGIN:VCALENDAR')
      expect(response.body).to include('END:VCALENDAR')
    end

    it "includes public events" do
      get calendar_ical_path(format: :ics)
      expect(response.body).to include('Public iCal Event')
    end

    it "excludes private events" do
      get calendar_ical_path(format: :ics)
      expect(response.body).not_to include('Private iCal Event')
    end

    it "excludes draft events" do
      get calendar_ical_path(format: :ics)
      expect(response.body).not_to include('Draft iCal Event')
    end

    it "includes VEVENT entries" do
      get calendar_ical_path(format: :ics)
      expect(response.body).to include('BEGIN:VEVENT')
      expect(response.body).to include('END:VEVENT')
    end

    it "includes event details in VEVENT" do
      get calendar_ical_path(format: :ics)
      expect(response.body).to include('SUMMARY:Public iCal Event')
      expect(response.body).to include('DTSTART')
      expect(response.body).to include('DTEND')
    end

    describe "time zone handling" do
      let(:occurs_at) { 3.days.from_now.change(hour: 18, min: 30) }

      before do
        public_event.occurrences.first.update!(occurs_at: occurs_at)
        get calendar_ical_path(format: :ics)
      end

      it "emits DTSTART as the UTC instant of the occurrence" do
        expect(response.body).to include("DTSTART:#{occurs_at.utc.strftime('%Y%m%dT%H%M%SZ')}")
      end

      it "does not emit the local wall clock, which clients read in their own zone" do
        expect(response.body).not_to include("DTSTART:#{occurs_at.strftime('%Y%m%dT%H%M%S')}")
      end

      it "suffixes every DATE-TIME with Z so none of them float" do
        date_times = response.body.lines.map(&:chomp).grep(/\A(DTSTART|DTEND|DTSTAMP)[:;]/)

        expect(date_times).not_to be_empty
        expect(date_times).to all(end_with('Z'))
      end

      it "does not reference a time zone it never defines" do
        expect(response.body).not_to include('TZID')
      end
    end

    it "advertises the display time zone for subscribers" do
      get calendar_ical_path(format: :ics)

      expect(response.body).to include("X-WR-TIMEZONE:#{Time.zone.tzinfo.name}")
    end

    it "only uses status values RFC 5545 permits" do
      get calendar_ical_path(format: :ics)

      statuses = response.body.lines.map(&:chomp).grep(/\ASTATUS:/)
      expect(statuses).not_to be_empty
      expect(statuses).to all(be_in(['STATUS:TENTATIVE', 'STATUS:CONFIRMED', 'STATUS:CANCELLED']))
    end

    it "gives each occurrence a stable UID so subscribers do not duplicate events" do
      get calendar_ical_path(format: :ics)
      first = response.body.lines.map(&:chomp).grep(/\AUID:/)

      get calendar_ical_path(format: :ics)
      second = response.body.lines.map(&:chomp).grep(/\AUID:/)

      expect(second).to eq(first)
      expect(second).not_to be_empty
    end
  end
end
