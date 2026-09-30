# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "RSS Feeds", type: :request do
  let!(:site_config) { create(:site_config) }
  let(:user) { create(:user) }

  describe "GET /events/rss (unified feed)" do
    let!(:public_event) { create(:event, visibility: 'public', status: 'active', draft: false) }
    let!(:members_event) { create(:event, :members_only, status: 'active', draft: false) }
    let!(:private_event) { create(:event, :private, status: 'active', draft: false) }
    let!(:draft_event) { create(:event, visibility: 'public', status: 'active', draft: true) }
    let!(:cancelled_event) { create(:event, :cancelled, visibility: 'public', draft: false) }

    it "returns RSS content type" do
      get events_rss_path(format: :rss)
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('application/rss+xml')
    end

    it "includes valid RSS structure" do
      get events_rss_path(format: :rss)
      expect(response.body).to include('<?xml version="1.0"')
      expect(response.body).to include('<rss version="2.0"')
      expect(response.body).to include('<channel>')
      expect(response.body).to include('</channel>')
      expect(response.body).to include('</rss>')
    end

    it "includes channel metadata" do
      get events_rss_path(format: :rss)
      expect(response.body).to include("<title>#{site_config.organization_name} Events</title>")
      expect(response.body).to include('<language>en-us</language>')
      expect(response.body).to include('atom:link')
    end

    it "includes public events" do
      get events_rss_path(format: :rss)
      expect(response.body).to include(public_event.title)
    end

    it "includes members events" do
      get events_rss_path(format: :rss)
      expect(response.body).to include(members_event.title)
    end

    it "excludes private events" do
      get events_rss_path(format: :rss)
      expect(response.body).not_to include(private_event.title)
    end

    it "excludes draft events" do
      get events_rss_path(format: :rss)
      expect(response.body).not_to include(draft_event.title)
    end

    it "excludes cancelled events" do
      get events_rss_path(format: :rss)
      expect(response.body).not_to include(cancelled_event.title)
    end

    it "does not require authentication" do
      get events_rss_path(format: :rss)
      expect(response).to have_http_status(:success)
    end

    context "with event details" do
      let!(:event_with_details) do
        create(:event,
               visibility: 'public',
               status: 'active',
               draft: false,
               description: "A great event description",
               more_info_url: "https://example.com/more-info")
      end
      let!(:location) { create(:location, name: "Main Hall") }

      before do
        event_with_details.update!(location: location)
      end

      it "includes event link" do
        get events_rss_path(format: :rss)
        expect(response.body).to include("<link>#{event_url(event_with_details)}</link>")
      end

      it "includes event guid" do
        get events_rss_path(format: :rss)
        expect(response.body).to include("<guid")
        expect(response.body).to include(event_url(event_with_details))
      end

      it "includes pubDate" do
        get events_rss_path(format: :rss)
        expect(response.body).to include("<pubDate>")
      end

      it "includes description with location" do
        get events_rss_path(format: :rss)
        expect(response.body).to include("Main Hall")
      end

      it "includes recurrence type category" do
        get events_rss_path(format: :rss)
        expect(response.body).to include("<category>Once</category>")
      end

      it "labels each open_to level distinctly" do
        create(:event, visibility: 'public', open_to: 'members', title: 'Members Feed Event')
        create(:event, visibility: 'public', open_to: 'private', title: 'Private Feed Event')
        get events_rss_path(format: :rss)
        items = Nokogiri::XML(response.body).xpath('//item')
        categories = ->(title) { items.find { |i| i.at('title').text == title }.xpath('category').map(&:text) }

        expect(categories.call('Members Feed Event')).to include('Members Only')
        expect(categories.call('Private Feed Event')).to include('Private')
        expect(categories.call('Private Feed Event')).not_to include('Members Only')
      end
    end

    context "with event banner" do
      it "includes enclosure for banner image" do
        create(:event, :with_banner, visibility: 'public', status: 'active', draft: false)
        get events_rss_path(format: :rss)
        expect(response.body).to include("<enclosure")
        expect(response.body).to include("image/jpeg")
      end
    end

    context "with upcoming occurrences" do
      let!(:event_with_occurrences) { create(:event, visibility: 'public', status: 'active', draft: false) }

      before do
        event_with_occurrences.occurrences.destroy_all
        create(:event_occurrence, event: event_with_occurrences, occurs_at: 3.days.from_now)
      end

      it "includes next occurrence date in description" do
        get events_rss_path(format: :rss)
        # Content is HTML-escaped in RSS
        expect(response.body).to include("&lt;strong&gt;Next:&lt;/strong&gt;")
      end
    end
  end

  describe "GET /events/:id/rss (per-event feed)" do
    let!(:event) { create(:event, visibility: 'public', status: 'active', draft: false, description: "Test event description") }
    let!(:occurrence1) { create(:event_occurrence, event: event, occurs_at: 1.week.from_now) }
    let!(:occurrence2) { create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now) }
    let!(:past_occurrence) { create(:event_occurrence, :past, event: event) }

    before do
      # Clear auto-generated occurrences and use our test ones
      event.occurrences.where.not(id: [occurrence1.id, occurrence2.id, past_occurrence.id]).destroy_all
    end

    it "returns RSS content type" do
      get rss_event_path(event, format: :rss)
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('application/rss+xml')
    end

    it "includes valid RSS structure" do
      get rss_event_path(event, format: :rss)
      expect(response.body).to include('<?xml version="1.0"')
      expect(response.body).to include('<rss version="2.0"')
      expect(response.body).to include('<channel>')
    end

    it "includes event-specific channel title" do
      get rss_event_path(event, format: :rss)
      expect(response.body).to include("<title>#{event.title} - #{site_config.organization_name}</title>")
    end

    it "includes event description in channel" do
      get rss_event_path(event, format: :rss)
      expect(response.body).to include(event.description.truncate(500))
    end

    it "includes event link" do
      get rss_event_path(event, format: :rss)
      expect(response.body).to include("<link>#{event_url(event)}</link>")
    end

    it "includes upcoming occurrences" do
      get rss_event_path(event, format: :rss)
      expect(response.body).to include(occurrence1.occurs_at.strftime('%B %d, %Y'))
      expect(response.body).to include(occurrence2.occurs_at.strftime('%B %d, %Y'))
    end

    it "excludes past occurrences" do
      get rss_event_path(event, format: :rss)
      expect(response.body).not_to include(past_occurrence.occurs_at.strftime('%B %d, %Y'))
    end

    it "includes occurrence links" do
      get rss_event_path(event, format: :rss)
      expect(response.body).to include(event_occurrence_url(occurrence1))
    end

    it "does not require authentication" do
      get rss_event_path(event, format: :rss)
      expect(response).to have_http_status(:success)
    end

    context "with occurrence details" do
      let!(:location) { create(:location, name: "Conference Room") }

      before do
        event.update!(location: location)
      end

      it "includes duration in description" do
        get rss_event_path(event, format: :rss)
        expect(response.body).to include("Duration")
      end

      it "includes location in description" do
        get rss_event_path(event, format: :rss)
        expect(response.body).to include("Conference Room")
      end
    end

    context "with a members-only event" do
      it "includes the open-to category" do
        event.update!(open_to: 'members')
        get rss_event_path(event, format: :rss)
        expect(response.body).to include("<category>Members Only</category>")
      end
    end

    context "with postponed occurrence" do
      it "includes status category for non-active occurrences" do
        create(:event_occurrence, :postponed, event: event, occurs_at: 3.weeks.from_now)
        get rss_event_path(event, format: :rss)
        expect(response.body).to include("<category>Postponed</category>")
      end
    end

    context "with private event" do
      let!(:private_event) { create(:event, :private, status: 'active', draft: false) }

      it "returns not found" do
        get rss_event_path(private_event, format: :rss)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with draft event" do
      let!(:draft_event) { create(:event, visibility: 'public', status: 'active', draft: true) }

      it "returns not found" do
        get rss_event_path(draft_event, format: :rss)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with members-only event" do
      let!(:members_event) { create(:event, :members_only, status: 'active', draft: false) }

      it "allows access without authentication" do
        get rss_event_path(members_event, format: :rss)
        expect(response).to have_http_status(:success)
      end
    end

    context "with event banner" do
      let!(:event_with_banner) { create(:event, :with_banner, visibility: 'public', status: 'active', draft: false) }

      before do
        create(:event_occurrence, event: event_with_banner, occurs_at: 1.week.from_now)
      end

      it "includes channel image" do
        get rss_event_path(event_with_banner, format: :rss)
        expect(response.body).to include("<image>")
      end
    end

    context "with more_info_url" do
      let!(:event_with_url) { create(:event, :with_more_info, visibility: 'public', status: 'active', draft: false) }

      before do
        create(:event_occurrence, event: event_with_url, occurs_at: 1.week.from_now)
      end

      it "includes more info link in description" do
        get rss_event_path(event_with_url, format: :rss)
        expect(response.body).to include("More information")
      end
    end
  end

  describe "RSS feed discovery" do
    it "events index page includes RSS autodiscovery link" do
      get events_path
      expect(response.body).to include('application/rss+xml')
    end
  end
end
