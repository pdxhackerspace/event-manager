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
        public_event = create(:event, :with_banner, visibility: 'public')
        public_occurrence = public_event.occurrences.first
        custom_image = public_event.event_images.create!(position: 99, in_pool: false)
        custom_image.image.attach(
          io: StringIO.new('fake occurrence image content'),
          filename: 'occurrence-banner.jpg',
          content_type: 'image/jpeg'
        )
        public_occurrence.update!(event_image: custom_image, custom_event_image: true)

        get event_occurrence_path(public_occurrence)

        expected_url = expected_blob_url(public_occurrence.banner)
        expect(meta_content('meta[property="og:image"]')).to eq(expected_url)
        expect(meta_content('meta[name="twitter:image"]')).to eq(expected_url)
      end

      it "falls back to the event banner for link preview images" do
        public_event = create(:event, :with_banner, visibility: 'public')
        public_occurrence = public_event.occurrences.first

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

      it "does not reassign the banner when inherit is submitted unchanged" do
        image = create(:event_image, :with_image, event: event, position: 0)
        event.update!(image_selection_mode: 'cycle', fixed_event_image_id: image.id, image_cycle_index: 3)
        occurrence.update!(event_image: image, custom_event_image: false)
        original_image_id = occurrence.event_image_id

        patch event_occurrence_path(occurrence),
              params: {
                event_occurrence: {
                  custom_description: 'Updated description',
                  image_source: 'inherit'
                }
              }

        occurrence.reload
        event.reload
        expect(occurrence.event_image_id).to eq(original_image_id)
        expect(event.image_cycle_index).to eq(3)
      end

      context "when switching from a custom image to inherit in cycle mode" do
        let!(:first_image) { create(:event_image, :with_image, event: event, position: 0) }
        let!(:second_image) { create(:event_image, :with_image, event: event, position: 1) }

        before do
          event.update!(image_selection_mode: 'cycle', fixed_event_image_id: first_image.id, image_cycle_index: 0)
          occurrence.update!(event_image: second_image, custom_event_image: true)
          patch event_occurrence_path(occurrence),
                params: { event_occurrence: { status: occurrence.status, image_source: 'inherit' } }
        end

        it "advances the cycle" do
          occurrence.reload
          event.reload
          expect(occurrence.custom_event_image?).to be false
          expect(occurrence.event_image).to eq(first_image)
          expect(event.image_cycle_index).to eq(1)
        end
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

  describe "POST /event_occurrences/:id/generate_ai_reminder" do
    before do
      sign_in user
      allow(OllamaService).to receive_messages(
        configured?: true,
        generate_short_reminder: 'Short reminder',
        generate_long_reminder: 'Long reminder'
      )
    end

    it "defaults to a short reminder when type is omitted" do
      post generate_ai_reminder_event_occurrence_path(occurrence),
           params: { days: 6 },
           as: :json

      expect(response).to have_http_status(:success)
      expect(OllamaService).to have_received(:generate_short_reminder).with(occurrence, 6)
      expect(JSON.parse(response.body)).to include('success' => true, 'message' => 'Short reminder')
    end

    it "generates a long reminder when type is long" do
      post generate_ai_reminder_event_occurrence_path(occurrence),
           params: { days: 1, type: 'long' },
           as: :json

      expect(response).to have_http_status(:success)
      expect(OllamaService).to have_received(:generate_long_reminder).with(occurrence, 1)
    end
  end

  describe "GET /event_occurrences/:id/ical" do
    let(:public_event) { create(:event, visibility: 'public', title: 'Exploit Workshop', duration: 240) }
    let(:public_occurrence) { public_event.occurrences.first }
    let(:occurs_at) { 3.days.from_now.change(hour: 18, min: 30) }

    before { public_occurrence.update!(occurs_at: occurs_at) }

    it "returns a downloadable calendar file" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('text/calendar')
      expect(response.headers['Content-Disposition']).to include('attachment')
    end

    it "names the file after the event and its local date" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response.headers['Content-Disposition'])
        .to include("exploit-workshop-#{occurs_at.strftime('%Y-%m-%d')}.ics")
    end

    it "emits DTSTART as the UTC instant of the occurrence" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response.body).to include("DTSTART:#{occurs_at.utc.strftime('%Y%m%dT%H%M%SZ')}")
    end

    it "emits DTEND advanced by the event duration" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response.body).to include("DTEND:#{(occurs_at + 240.minutes).utc.strftime('%Y%m%dT%H%M%SZ')}")
    end

    # Regression: the UTC instant used to be written without a "Z", so Apple
    # Calendar read 6:30 PM Pacific as 1:30 AM local on the following day.
    it "does not emit a UTC instant as a floating time" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response.body).not_to match(/^DTSTART:\d{8}T\d{6}$/)
    end

    it "suffixes every DATE-TIME with Z so none of them float" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      date_times = response.body.lines.map(&:chomp).grep(/\A(DTSTART|DTEND|DTSTAMP)[:;]/)

      expect(date_times).not_to be_empty
      expect(date_times).to all(end_with('Z'))
    end

    it "includes a single VEVENT for the occurrence" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response.body.scan('BEGIN:VEVENT').size).to eq(1)
      expect(response.body).to include('SUMMARY:Exploit Workshop')
    end

    it "links back to the occurrence page" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response.body.gsub(/\r\n[ \t]/, '')).to include(event_occurrence_url(public_occurrence, host: 'www.example.com'))
    end

    it "omits METHOD because the file is imported rather than published" do
      get ical_event_occurrence_path(public_occurrence, format: :ics)

      expect(response.body).not_to include('METHOD:')
    end
  end
end
