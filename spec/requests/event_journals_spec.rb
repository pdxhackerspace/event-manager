require 'rails_helper'

RSpec.describe 'EventJournals', type: :request do
  let(:admin) { create(:user, :admin) }

  # Each entry gets its own event so the rendered title identifies it.
  def journal(title, created_at:, action: 'updated')
    create(:event_journal,
           event: create(:event, title: title),
           user: admin,
           action: action,
           created_at: created_at)
  end

  describe 'GET /event_journals' do
    context 'as an admin' do
      before { sign_in admin }

      it 'renders the log' do
        journal('Logged Event', created_at: 1.hour.ago)

        get event_journals_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Logged Event')
      end

      it 'says so when there are no entries' do
        get event_journals_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('No journal entries recorded yet.')
      end

      it 'renders entries whose event has since been deleted' do
        # Events are soft deleted, so the row survives but the default scope
        # hides it and journal.event reads back as nil.
        journal('Doomed Event', created_at: 1.hour.ago).event.destroy

        get event_journals_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('Doomed Event')
      end

      it 'renders an entry for an occurrence' do
        create(:event_journal, :for_occurrence, user: admin)

        get event_journals_path

        expect(response).to have_http_status(:ok)
      end

      it 'renders entries whose user has since been deleted' do
        author = create(:user, name: 'Departed Author')
        create(:event_journal, event: create(:event, title: 'Outlives Author'), user: author)
        author.destroy!

        get event_journals_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('(deleted user)')
        expect(response.body).not_to include('Departed Author')
      end
    end

    context 'as a non-admin' do
      it 'redirects to the root path' do
        sign_in create(:user)

        get event_journals_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('not authorized')
      end
    end

    context 'when signed out' do
      it 'requires sign in' do
        get event_journals_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'pagination' do
    # Shrink the page so these examples need three rows instead of 101.
    before do
      stub_const('EventJournalsController::PER_PAGE', 2)
      sign_in admin
      journal('Newest Entry', created_at: 1.minute.ago)
      journal('Middle Entry', created_at: 1.hour.ago)
      journal('Oldest Entry', created_at: 1.day.ago)
    end

    it 'fills the first page with the newest entries' do
      get event_journals_path

      expect(response.body).to include('Newest Entry').and include('Middle Entry')
      expect(response.body).not_to include('Oldest Entry')
    end

    it 'orders newest first' do
      get event_journals_path

      expect(response.body.index('Newest Entry')).to be < response.body.index('Middle Entry')
    end

    it 'offers a next page but not a previous one' do
      get event_journals_path

      expect(response.body).to include('Page 1')
      expect(next_link_enabled?).to be(true)
      expect(prev_link_enabled?).to be(false)
    end

    it 'serves the remainder on the last page' do
      get event_journals_path(page: 2)

      expect(response.body).to include('Oldest Entry')
      expect(response.body).not_to include('Newest Entry')
      expect(next_link_enabled?).to be(false)
      expect(prev_link_enabled?).to be(true)
    end

    it 'returns an empty page past the end rather than erroring' do
      get event_journals_path(page: 99)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No journal entries recorded yet.')
    end

    it 'treats a non-numeric page as the first page' do
      get event_journals_path(page: 'banana')

      expect(response.body).to include('Page 1').and include('Newest Entry')
    end

    it 'clamps a negative page to the first page' do
      get event_journals_path(page: -5)

      expect(response.body).to include('Page 1').and include('Newest Entry')
    end
  end

  # The nav marks unavailable directions with a disabled list item.
  def next_link_enabled?
    !response.body.match?(/<li class="page-item disabled">\s*<a[^>]*aria-label="Next"/m)
  end

  def prev_link_enabled?
    !response.body.match?(/<li class="page-item disabled">\s*<a[^>]*aria-label="Previous"/m)
  end
end
