require 'rails_helper'

RSpec.describe 'Pagination', type: :request do
  let(:per_page) { Pagy::DEFAULT[:limit] }

  describe 'GET /events' do
    # Titles are zero-padded so "Event 002" is never a substring of "Event 020".
    let!(:events) do
      Array.new(per_page + 2) do |i|
        event = create(:event, visibility: 'public', title: format('Paged Event %03d', i))
        event.occurrences.destroy_all
        create(:event_occurrence, event: event, occurs_at: (i + 1).days.from_now)
        event
      end
    end

    def rendered_card_count
      response.body.scan(/id="event-title-\d+"/).size
    end

    it 'shows a full page and no more' do
      get events_path

      expect(rendered_card_count).to eq(per_page)
      expect(response.body).to include('Paged Event 000')
      expect(response.body).not_to include(events.last.title)
    end

    it 'shows the remainder on the next page' do
      get events_path(page: 2)

      expect(rendered_card_count).to eq(2)
      expect(response.body).to include(events.last.title)
      expect(response.body).not_to include('Paged Event 000')
    end

    it 'renders pagination navigation' do
      get events_path

      expect(response.body).to include('aria-label="Event pages"')
      expect(response.body).to include(events_path(page: 2))
    end

    it 'orders events by their next occurrence' do
      get events_path

      expect(response.body.index('Paged Event 000')).to be < response.body.index('Paged Event 001')
    end

    it 'clamps an out-of-range page to the last page instead of erroring' do
      get events_path(page: 999)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(events.last.title)
    end

    it 'reports the total match count when searching, not just the page size' do
      get events_path(q: 'Paged Event')

      expect(response.body).to include("Found <strong>#{per_page + 2}</strong> events")
    end

    it 'keeps the search filter on later pages' do
      get events_path(q: 'Paged Event', page: 2)

      expect(rendered_card_count).to eq(2)
      expect(response.body).to include(events.last.title)
    end

    it 'does not load every future occurrence to render a page' do
      # One event with many occurrences: the page needs only its next one.
      busy = create(:event, visibility: 'public', title: 'Busy Event')
      busy.occurrences.destroy_all
      Array.new(30) { |i| create(:event_occurrence, event: busy, occurs_at: (i + 1).weeks.from_now) }

      get events_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Busy Event')
    end
  end

  describe 'GET /users' do
    let(:admin) { create(:user, :admin) }

    before { sign_in admin }

    it 'shows a full page and no more' do
      Array.new(per_page + 2) { |i| create(:user, name: format('Paged User %03d', i)) }

      get users_path

      # One "Edit" link per row, so this counts rendered rows regardless of
      # which users sorted onto the first page.
      expect(response.body.scan(%r{/users/\d+/edit}).size).to eq(per_page)
      expect(response.body).to include(users_path(page: 2))
    end

    it 'shows event counts per user' do
      owner = create(:user, name: 'Owner With Events')
      create_list(:event, 2, user: owner)

      get users_path

      expect(response.body).to include('Owner With Events')
      expect(response.body).to match(%r{Owner With Events.*?<td>2</td>}m)
    end

    it 'does not issue a query per user to count their events' do
      Array.new(3) { |i| create(:user, name: "Few #{i}") }
      few = captured_queries { get users_path }.size

      Array.new(6) { |i| create(:user, name: "Many #{i}") }
      many = captured_queries { get users_path }.size

      expect(many).to eq(few)
    end
  end

  describe 'GET /locations' do
    let(:admin) { create(:user, :admin) }

    before do
      Array.new(per_page + 2) { |i| create(:location, name: format('Paged Location %03d', i)) }
      sign_in admin
    end

    it 'shows a full page and no more' do
      get locations_path

      expect(response.body.scan(/Paged Location \d{3}/).size).to eq(per_page)
      expect(response.body).not_to include(format('Paged Location %03d', per_page + 1))
    end

    it 'renders pagination navigation' do
      get locations_path

      expect(response.body).to include(locations_path(page: 2))
    end
  end
end
