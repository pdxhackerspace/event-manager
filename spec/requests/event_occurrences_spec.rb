require 'rails_helper'

RSpec.describe "EventOccurrences", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:event) { create(:event, user: user) }
  let(:occurrence) { event.occurrences.first }

  def meta_content(selector)
    Nokogiri::HTML(response.body).at_css(selector)&.[]('content')
  end

  def expected_blob_url(attachment)
    rails_blob_url(attachment, host: 'www.example.com')
  end

  describe "GET /event_occurrences/:id" do
    context "as a guest with public event" do
      let(:public_event) { create(:event, visibility: 'public') }
      let(:public_occurrence) { public_event.occurrences.first }

      it "shows the occurrence" do
        get event_occurrence_path(public_occurrence)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(public_event.title)
      end

      it "uses the occurrence banner for link preview images" do
        public_event.banner_image.attach(
          io: StringIO.new('fake event image content'),
          filename: 'event-banner.jpg',
          content_type: 'image/jpeg'
        )
        public_occurrence.banner_image.attach(
          io: StringIO.new('fake occurrence image content'),
          filename: 'occurrence-banner.jpg',
          content_type: 'image/jpeg'
        )

        get event_occurrence_path(public_occurrence)

        expected_url = expected_blob_url(public_occurrence.banner_image)
        expect(meta_content('meta[property="og:image"]')).to eq(expected_url)
        expect(meta_content('meta[name="twitter:image"]')).to eq(expected_url)
      end

      it "falls back to the event banner for link preview images" do
        public_event.banner_image.attach(
          io: StringIO.new('fake event image content'),
          filename: 'event-banner.jpg',
          content_type: 'image/jpeg'
        )

        get event_occurrence_path(public_occurrence)

        expected_url = expected_blob_url(public_event.banner_image)
        expect(meta_content('meta[property="og:image"]')).to eq(expected_url)
        expect(meta_content('meta[name="twitter:image"]')).to eq(expected_url)
      end
    end

    context "as a logged-in user" do
      before { sign_in user }

      it "shows the occurrence" do
        get event_occurrence_path(occurrence)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /event_occurrences/:id/edit" do
    context "as a guest" do
      it "redirects to sign in" do
        get edit_event_occurrence_path(occurrence)
        expect(response).to have_http_status(:redirect)
      end
    end

    context "as the event host" do
      before { sign_in user }

      it "shows the edit form" do
        get edit_event_occurrence_path(occurrence)
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Edit Occurrence")
      end
    end

    context "as a different user" do
      before { sign_in other_user }

      it "redirects with unauthorized message" do
        get edit_event_occurrence_path(occurrence)
        expect(response).to have_http_status(:redirect)
      end
    end

    context "as an admin" do
      before { sign_in admin }

      it "shows the edit form" do
        get edit_event_occurrence_path(occurrence)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "PATCH /event_occurrences/:id" do
    let(:update_params) do
      {
        event_occurrence: {
          custom_description: "Custom description for this occurrence"
        }
      }
    end

    context "as the event host" do
      before { sign_in user }

      it "updates the occurrence" do
        patch event_occurrence_path(occurrence), params: update_params
        occurrence.reload
        expect(occurrence.custom_description).to eq("Custom description for this occurrence")
      end

      it "redirects to the occurrence" do
        patch event_occurrence_path(occurrence), params: update_params
        expect(response).to redirect_to(event_occurrence_path(occurrence))
      end

      it "updates occurs_at when provided" do
        new_time = 2.weeks.from_now.change(sec: 0)
        patch event_occurrence_path(occurrence),
              params: {
                event_occurrence: {
                  occurs_at: new_time.strftime('%Y-%m-%dT%H:%M')
                }
              }
        occurrence.reload
        expect(occurrence.occurs_at).to be_within(1.second).of(new_time)
      end

      it "keeps the slug stable when occurs_at changes" do
        old_slug = occurrence.slug
        new_time = occurrence.occurs_at + 3.days
        patch event_occurrence_path(occurrence),
              params: {
                event_occurrence: {
                  occurs_at: new_time.strftime('%Y-%m-%dT%H:%M')
                }
              }
        occurrence.reload
        expect(occurrence.slug).to eq(old_slug)
      end
    end

    context "as a different user" do
      before { sign_in other_user }

      it "does not update the occurrence" do
        patch event_occurrence_path(occurrence), params: update_params
        occurrence.reload
        expect(occurrence.custom_description).to be_nil
      end
    end
  end

  describe "DELETE /event_occurrences/:id" do
    context "as the event host" do
      before { sign_in user }

      it "deletes the occurrence" do
        occurrence.id
        expect do
          delete event_occurrence_path(occurrence)
        end.to change(EventOccurrence, :count).by(-1)
      end

      it "does not delete the event" do
        event_id = event.id
        delete event_occurrence_path(occurrence)
        expect(Event.exists?(event_id)).to be true
      end

      it "redirects to the event" do
        delete event_occurrence_path(occurrence)
        expect(response).to redirect_to(event_path(event))
      end
    end

    context "as a different user" do
      before { sign_in other_user }

      it "does not delete the occurrence" do
        occurrence.id
        expect do
          delete event_occurrence_path(occurrence)
        end.not_to change(EventOccurrence, :count)
      end
    end
  end

  describe "POST /event_occurrences/:id/postpone" do
    let(:postpone_params) do
      {
        postponed_until: 2.weeks.from_now,
        reason: "Speaker unavailable"
      }
    end

    context "as the event host" do
      before { sign_in user }

      it "postpones the occurrence" do
        post postpone_event_occurrence_path(occurrence), params: postpone_params
        occurrence.reload
        expect(occurrence.status).to eq('postponed')
      end

      it "sets the postponed_until date" do
        post postpone_event_occurrence_path(occurrence), params: postpone_params
        occurrence.reload
        expect(occurrence.postponed_until).to be_present
      end

      it "sets the reason" do
        post postpone_event_occurrence_path(occurrence), params: postpone_params
        occurrence.reload
        expect(occurrence.cancellation_reason).to eq("Speaker unavailable")
      end

      it "does not affect other occurrences" do
        other_occurrence = event.occurrences.create!(occurs_at: 2.weeks.from_now)
        post postpone_event_occurrence_path(occurrence), params: postpone_params
        other_occurrence.reload
        expect(other_occurrence.status).to eq('active')
      end
    end
  end

  describe "POST /event_occurrences/:id/cancel" do
    let(:cancel_params) do
      { reason: "Weather conditions" }
    end

    context "as the event host" do
      before { sign_in user }

      it "cancels the occurrence" do
        post cancel_event_occurrence_path(occurrence), params: cancel_params
        occurrence.reload
        expect(occurrence.status).to eq('cancelled')
      end

      it "sets the reason" do
        post cancel_event_occurrence_path(occurrence), params: cancel_params
        occurrence.reload
        expect(occurrence.cancellation_reason).to eq("Weather conditions")
      end
    end
  end

  describe "POST /event_occurrences/:id/reactivate" do
    let(:cancelled_occurrence) { create(:event_occurrence, :cancelled, event: event) }

    context "as the event host" do
      before { sign_in user }

      it "reactivates the occurrence" do
        post reactivate_event_occurrence_path(cancelled_occurrence)
        cancelled_occurrence.reload
        expect(cancelled_occurrence.status).to eq('active')
      end

      it "clears the cancellation_reason" do
        post reactivate_event_occurrence_path(cancelled_occurrence)
        cancelled_occurrence.reload
        expect(cancelled_occurrence.cancellation_reason).to be_nil
      end
    end
  end
end
