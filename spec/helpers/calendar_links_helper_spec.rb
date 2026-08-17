# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarLinksHelper, type: :helper do
  let(:event) { create(:event, title: 'Test Event', more_info_url: 'https://example.com/info') }
  let(:location) { create(:location, name: 'Main Hall') }
  let(:occurrence) do
    create(:event_occurrence, event: event, occurs_at: Time.zone.parse('2025-06-15 19:00'), location: location)
  end

  before do
    allow(ENV).to receive(:fetch).with('APP_HOST', anything).and_return('example.com')
  end

  describe '#google_calendar_url' do
    it 'returns a Google Calendar URL' do
      url = helper.google_calendar_url(occurrence)

      expect(url).to start_with('https://calendar.google.com/calendar/render')
    end

    it 'includes event title' do
      url = helper.google_calendar_url(occurrence)

      expect(url).to include('Test+Event')
    end

    it 'includes dates parameter' do
      url = helper.google_calendar_url(occurrence)

      expect(url).to include('dates=')
    end

    it 'includes location' do
      url = helper.google_calendar_url(occurrence)

      expect(url).to include('Main+Hall')
    end

    it 'includes action TEMPLATE' do
      url = helper.google_calendar_url(occurrence)

      expect(url).to include('action=TEMPLATE')
    end
  end

  describe '#outlook_calendar_url' do
    it 'returns an Outlook.com URL' do
      url = helper.outlook_calendar_url(occurrence)

      expect(url).to start_with('https://outlook.live.com')
    end

    it 'includes event subject' do
      url = helper.outlook_calendar_url(occurrence)

      expect(url).to include('Test+Event')
    end

    it 'includes start and end times' do
      url = helper.outlook_calendar_url(occurrence)

      expect(url).to include('startdt=')
      expect(url).to include('enddt=')
    end

    it 'includes location' do
      url = helper.outlook_calendar_url(occurrence)

      expect(url).to include('Main+Hall')
    end
  end

  describe '#office365_calendar_url' do
    it 'returns an Office 365 URL' do
      url = helper.office365_calendar_url(occurrence)

      expect(url).to start_with('https://outlook.office.com')
    end

    it 'includes compose path' do
      url = helper.office365_calendar_url(occurrence)

      expect(url).to include('deeplink/compose')
    end
  end

  describe '#yahoo_calendar_url' do
    it 'returns a Yahoo Calendar URL' do
      url = helper.yahoo_calendar_url(occurrence)

      expect(url).to start_with('https://calendar.yahoo.com')
    end

    it 'includes event title' do
      url = helper.yahoo_calendar_url(occurrence)

      expect(url).to include('Test+Event')
    end

    it 'includes start time' do
      url = helper.yahoo_calendar_url(occurrence)

      expect(url).to include('st=')
    end

    it 'includes duration' do
      url = helper.yahoo_calendar_url(occurrence)

      expect(url).to include('dur=')
    end

    it 'includes location' do
      url = helper.yahoo_calendar_url(occurrence)

      expect(url).to include('Main+Hall')
    end
  end

  describe '#apple_calendar_url' do
    it 'returns iCal download path' do
      url = helper.apple_calendar_url(occurrence)

      expect(url).to include('ical')
      expect(url).to include(occurrence.to_param)
    end
  end

  describe '#build_calendar_description' do
    it 'includes occurrence description' do
      occurrence.update!(custom_description: 'Custom desc')

      description = helper.send(:build_calendar_description, occurrence)

      expect(description).to include('Custom desc')
    end

    it 'includes more info URL' do
      description = helper.send(:build_calendar_description, occurrence)

      expect(description).to include('https://example.com/info')
    end

    it 'includes event page URL' do
      description = helper.send(:build_calendar_description, occurrence)

      expect(description).to include('Event page:')
    end
  end

  describe 'date formatting' do
    it 'formats times in ISO8601 for Google Calendar' do
      url = helper.google_calendar_url(occurrence)

      # Google Calendar uses compact ISO format: 20250615T190000Z
      expect(url).to match(/dates=\d{8}T\d{6}Z/)
    end

    it 'formats times in ISO8601 for Outlook' do
      url = helper.outlook_calendar_url(occurrence)

      # Outlook uses full ISO8601: 2025-06-15T19:00:00Z
      expect(url).to match(/startdt=\d{4}-\d{2}-\d{2}T/)
    end
  end
end
