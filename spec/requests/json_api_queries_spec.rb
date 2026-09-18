require 'rails_helper'

# These feeds are public and unpaginated, so their cost has to stay flat as the
# event count grows. Exact query counts are not asserted: Rails' per-request
# query cache makes them vary by a query or two depending on how preload binds
# line up. The ceilings below are far under what one query per row would need.
RSpec.describe 'JSON feed query behavior', type: :request do
  # Mirrors the blob record Spectra6BannerJob creates. Only the record matters
  # here: the feed builds a URL from it and never reads the file.
  def create_spectra6_variant(attachment)
    ActiveStorage::Blob.create!(
      key: Spectra6BannerJob.variant_key(attachment.blob),
      filename: 'banner-spectra6.png',
      content_type: 'image/png',
      byte_size: 16,
      checksum: Digest::MD5.base64digest('spectra6'),
      service_name: ActiveStorage::Blob.service.name
    )
  end

  def create_event_with_banner(title)
    event = create(:event, :with_banner, visibility: 'public', title: title)
    event.reload
    create_spectra6_variant(event.fallback_event_image.image)
    event
  end

  # SiteConfig is a singleton created on first request; creating it here keeps
  # that one-off insert out of the measurements.
  before { SiteConfig.current }

  describe 'GET /events.json' do
    it 'stays flat as the number of events grows' do
      4.times { |i| create_event_with_banner("Small #{i}") }
      small = captured_queries { get events_path, headers: { 'Accept' => 'application/json' } }.size
      expect(response).to have_http_status(:success)

      16.times { |i| create_event_with_banner("Large #{i}") }
      large = captured_queries { get events_path, headers: { 'Accept' => 'application/json' } }.size

      expect(response).to have_http_status(:success)
      # 20 events; one query per row would be 20+ on top of the fixed set.
      expect(large).to be <= small + 3
      expect(large).to be < 20
    end

    it 'looks up Spectra6 variants in a single query' do
      5.times { |i| create_event_with_banner("Banner #{i}") }

      queries = captured_queries { get events_path, headers: { 'Accept' => 'application/json' } }

      expect(queries.grep(/FROM "active_storage_blobs".+"key"/).size).to eq(1)
    end

    it 'does not query pooled images per event to resolve the fallback banner' do
      5.times { |i| create_event_with_banner("Pooled #{i}") }

      queries = captured_queries { get events_path, headers: { 'Accept' => 'application/json' } }

      # The preloads fetch event_images by event_id in bulk; a per-event
      # `pooled.first` would show up as a query filtering on in_pool.
      expect(queries.grep(/FROM "event_images".+"in_pool"/)).to be_empty
    end

    it 'does not run the paginated HTML page load' do
      create_event_with_banner('Only Event')

      queries = captured_queries { get events_path, headers: { 'Accept' => 'application/json' } }

      expect(queries.grep(/next_occurs_at/)).to be_empty
    end

    it 'still returns the Spectra6 banner URL for every event' do
      3.times { |i| create_event_with_banner("Banner #{i}") }

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      expect(json['events'].size).to eq(3)
      expect(json['events'].pluck('spectra6_banner_url')).to all(be_present)
      expect(json['occurrences'].pluck('spectra6_banner_url')).to all(be_present)
    end

    it 'returns a null Spectra6 URL when the variant has not been generated' do
      create(:event, :with_banner, visibility: 'public', title: 'No Variant')

      get events_path, headers: { 'Accept' => 'application/json' }
      json = JSON.parse(response.body)

      event = json['events'].find { |e| e['title'] == 'No Variant' }
      expect(event['banner_url']).to be_present
      expect(event['spectra6_banner_url']).to be_nil
    end
  end

  describe 'GET /events/eink' do
    it 'stays flat as the number of events grows' do
      4.times { |i| create(:event, visibility: 'public', title: "Sign #{i}", sign_feed: true) }
      small = captured_queries { get events_eink_path }.size
      expect(response).to have_http_status(:success)

      16.times { |i| create(:event, visibility: 'public', title: "More Sign #{i}", sign_feed: true) }
      large = captured_queries { get events_eink_path }.size

      expect(response).to have_http_status(:success)
      expect(large).to be <= small
    end
  end

  describe 'GET /events/rss' do
    it 'stays flat as the number of events grows' do
      4.times { |i| create_event_with_banner("Feed #{i}") }
      small = captured_queries { get events_rss_path(format: :rss) }.size
      expect(response).to have_http_status(:success)

      16.times { |i| create_event_with_banner("More Feed #{i}") }
      large = captured_queries { get events_rss_path(format: :rss) }.size

      expect(response).to have_http_status(:success)
      expect(large).to be <= small + 2
      expect(large).to be < 20
    end

    it 'resolves each event next date without a query per item' do
      5.times { |i| create(:event, visibility: 'public', title: "Dated #{i}") }

      queries = captured_queries { get events_rss_path(format: :rss) }

      expect(queries.grep(/DISTINCT ON \(event_occurrences.event_id\)/).size).to eq(1)
    end
  end
end
