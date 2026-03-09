require 'rails_helper'

RSpec.describe "Events", type: :request do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:other_user) { create(:user) }

  describe "GET /events" do
    let!(:public_event) { create(:event, visibility: 'public') }
    let!(:members_event) { create(:event, :members_only) }
    let!(:private_event) { create(:event, :private) }

    context "as a guest" do
      it "shows public events only" do
        get events_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(public_event.title)
        expect(response.body).not_to include(members_event.title)
        expect(response.body).not_to include(private_event.title)
      end
    end

    context "as a logged-in user" do
      before { sign_in user }

      it "shows public and members events" do
        get events_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(public_event.title)
        expect(response.body).to include(members_event.title)
        expect(response.body).not_to include(private_event.title)
      end
    end

    context "as an admin" do
      before { sign_in admin }

      it "shows all events" do
        get events_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(public_event.title)
        expect(response.body).to include(members_event.title)
        expect(response.body).to include(private_event.title)
      end
    end
  end

  describe "GET /events/:id" do
    let(:event) { create(:event, visibility: 'public') }

    context "as a guest" do
      context "with a public event" do
        it "shows the event" do
          get event_path(event)
          expect(response).to have_http_status(:success)
          expect(response.body).to include(event.title)
        end
      end

      context "with a private event" do
        let(:private_event) { create(:event, :private) }

        it "redirects with unauthorized message" do
          get event_path(private_event)
          expect(response).to have_http_status(:redirect)
          follow_redirect!
          expect(response.body).to include("not authorized")
        end
      end
    end

    context "as a logged-in user" do
      before { sign_in user }

      it "shows the event" do
        get event_path(event)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /events/new" do
    context "as a guest" do
      it "redirects to sign in" do
        get new_event_path
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "as a logged-in admin" do
      let(:admin) { create(:user, role: 'admin') }

      before { sign_in admin }

      it "shows the new event form" do
        get new_event_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("New Event")
      end
    end

    context "as a regular user" do
      before { sign_in user }

      it "redirects with unauthorized" do
        get new_event_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /events" do
    let(:event_params) do
      {
        event: {
          title: "Test Event",
          description: "Test Description",
          start_time: 1.week.from_now,
          duration: 120,
          recurrence_type: "once",
          visibility: "public",
          open_to: "public"
        }
      }
    end

    context "as a guest" do
      it "redirects to sign in" do
        post events_path, params: event_params
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "does not create an event" do
        expect do
          post events_path, params: event_params
        end.not_to change(Event, :count)
      end
    end

    context "as a logged-in admin" do
      let(:admin) { create(:user, role: 'admin') }

      before { sign_in admin }

      context "with valid params" do
        it "creates a new event" do
          expect do
            post events_path, params: event_params
          end.to change(Event, :count).by(1)
        end

        it "creates occurrences for the event" do
          post events_path, params: event_params
          event = Event.last
          expect(event.occurrences).to be_present
        end

        it "adds the creator as a host" do
          post events_path, params: event_params
          event = Event.last
          expect(event).to be_present
          expect(event.user).to eq(admin)
          expect(event.event_hosts.count).to eq(1)
          expect(event.hosts).to include(admin)
        end

        it "redirects to the event" do
          post events_path, params: event_params
          expect(response).to redirect_to(event_path(Event.last))
        end
      end

      context "with invalid params" do
        let(:invalid_params) do
          { event: { title: "" } }
        end

        it "does not create an event" do
          expect do
            post events_path, params: invalid_params
          end.not_to change(Event, :count)
        end

        it "renders the new template" do
          post events_path, params: invalid_params
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context "as a regular user" do
      before { sign_in user }

      it "redirects with unauthorized" do
        post events_path, params: event_params
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET /events/:id/edit" do
    let(:event) { create(:event, user: user) }

    context "as a guest" do
      it "redirects to sign in" do
        get edit_event_path(event)
        expect(response).to have_http_status(:redirect)
      end
    end

    context "as the event creator" do
      before { sign_in user }

      it "shows the edit form" do
        get edit_event_path(event)
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Edit Event")
      end
    end

    context "as a different user" do
      before { sign_in other_user }

      it "redirects with unauthorized message" do
        get edit_event_path(event)
        expect(response).to have_http_status(:redirect)
      end
    end

    context "as an event host (not creator)" do
      before do
        event.add_host(other_user)
        sign_in other_user
      end

      it "shows the edit form" do
        get edit_event_path(event)
        expect(response).to have_http_status(:success)
      end
    end

    context "as an admin" do
      before { sign_in admin }

      it "shows the edit form" do
        get edit_event_path(event)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "PATCH /events/:id" do
    let(:event) { create(:event, user: user, title: "Old Title") }
    let(:update_params) do
      { event: { title: "New Title" } }
    end

    context "as the event creator" do
      before { sign_in user }

      it "updates the event" do
        patch event_path(event), params: update_params
        event.reload
        expect(event.title).to eq("New Title")
      end

      it "redirects to the event" do
        patch event_path(event), params: update_params
        expect(response).to redirect_to(event_path(event))
      end
    end

    context "as a different user" do
      before { sign_in other_user }

      it "does not update the event" do
        patch event_path(event), params: update_params
        event.reload
        expect(event.title).to eq("Old Title")
      end
    end
  end

  describe "DELETE /events/:id" do
    let!(:event) { create(:event, user: user) }

    context "as the event creator" do
      before { sign_in user }

      it "deletes the event" do
        expect do
          delete event_path(event)
        end.to change(Event, :count).by(-1)
      end

      it "redirects to events index" do
        delete event_path(event)
        expect(response).to redirect_to(events_url)
      end
    end

    context "as a different user" do
      before { sign_in other_user }

      it "does not delete the event" do
        expect do
          delete event_path(event)
        end.not_to change(Event, :count)
      end
    end

    context "as an admin" do
      before { sign_in admin }

      it "deletes the event" do
        expect do
          delete event_path(event)
        end.to change(Event, :count).by(-1)
      end
    end
  end

  describe "POST /events/:id/postpone" do
    let(:event) { create(:event, user: user, status: 'active') }
    let(:postpone_params) do
      {
        postponed_until: 1.week.from_now,
        reason: "Weather conditions"
      }
    end

    context "as the event creator" do
      before { sign_in user }

      it "postpones the event" do
        # Verify the user is set up as a host
        expect(event.hosted_by?(user)).to be(true)

        post postpone_event_path(event), params: postpone_params

        # Check flash for success/failure message
        follow_redirect!
        expect(flash[:notice]).to eq('Event was postponed.'),
                                  "Expected success notice. Flash: #{flash.inspect}"

        event.reload
        expect(event.status).to eq('postponed')
      end

      it "sets the postponed_until date" do
        post postpone_event_path(event), params: postpone_params
        event.reload
        expect(event.postponed_until).to be_present
      end

      it "sets the reason" do
        post postpone_event_path(event), params: postpone_params
        event.reload
        expect(event.cancellation_reason).to eq("Weather conditions")
      end

      it "redirects to the event" do
        post postpone_event_path(event), params: postpone_params
        expect(response).to redirect_to(event_path(event))
      end
    end

    context "as a different user" do
      before { sign_in other_user }

      it "does not postpone the event" do
        post postpone_event_path(event), params: postpone_params
        event.reload
        expect(event.status).to eq('active')
      end
    end
  end

  describe "POST /events/:id/cancel" do
    let(:event) { create(:event, user: user, status: 'active') }
    let(:cancel_params) do
      { reason: "Insufficient registrations" }
    end

    context "as the event creator" do
      before { sign_in user }

      it "cancels the event" do
        post cancel_event_path(event), params: cancel_params
        event.reload
        expect(event.status).to eq('cancelled')
      end

      it "sets the reason" do
        post cancel_event_path(event), params: cancel_params
        event.reload
        expect(event.cancellation_reason).to eq("Insufficient registrations")
      end
    end
  end

  describe "POST /events/:id/reactivate" do
    let(:event) { create(:event, :cancelled, user: user) }

    context "as the event creator" do
      before { sign_in user }

      it "reactivates the event" do
        post reactivate_event_path(event)
        event.reload
        expect(event.status).to eq('active')
      end

      it "clears the cancellation_reason" do
        post reactivate_event_path(event)
        event.reload
        expect(event.cancellation_reason).to be_nil
      end
    end
  end

  describe "GET /events/:token/ical" do
    let(:event) { create(:event, visibility: 'public') }

    it "returns an ical feed" do
      get event_ical_path(event.ical_token, format: :ics)
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('text/calendar')
    end

    it "includes event information" do
      get event_ical_path(event.ical_token, format: :ics)
      expect(response.body).to include(event.title)
    end

    it "does not require authentication" do
      get event_ical_path(event.ical_token, format: :ics)
      expect(response).to have_http_status(:success)
    end
  end
end
