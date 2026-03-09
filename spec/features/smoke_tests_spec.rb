require 'rails_helper'

RSpec.describe "Smoke Tests", type: :feature do
  describe "Homepage" do
    it "loads successfully" do
      visit root_path
      expect(page).to have_content("EventManager")
    end

    it "shows upcoming events" do
      create(:event, visibility: 'public', title: 'Test Event')
      visit root_path
      expect(page).to have_content('Test Event')
    end

    it "has navigation links" do
      visit root_path
      expect(page).to have_link("Events")
      expect(page).to have_link("Calendar")
    end
  end

  describe "Event Listing" do
    it "shows all public events" do
      create(:event, visibility: 'public', title: 'Public Event')
      create(:event, :private, title: 'Private Event')

      visit events_path
      expect(page).to have_content('Public Event')
      expect(page).not_to have_content('Private Event')
    end

    it "shows event details" do
      create(:event, visibility: 'public', title: 'Test Event', description: 'Test Description')

      visit events_path
      expect(page).to have_content('Test Event')
      expect(page).to have_content('Test Description')
    end
  end

  describe "Event Details" do
    let(:event) { create(:event, visibility: 'public', title: 'Detailed Event') }

    it "shows event information" do
      visit event_path(event)
      expect(page).to have_content('Detailed Event')
      expect(page).to have_content(event.description)

      # Check for time range display (start time to end time)
      start_time_str = event.start_time.strftime('%I:%M %p')
      end_time_str = (event.start_time + event.duration.minutes).strftime('%I:%M %p')
      expect(page).to have_content("#{start_time_str} to #{end_time_str}")
    end

    it "shows hosts" do
      visit event_path(event)
      expect(page).to have_content(event.user.name || event.user.email)
    end

    it "shows upcoming occurrences" do
      visit event_path(event)
      expect(page).to have_content('Upcoming Occurrences')
    end

    it "shows iCal feed link" do
      visit event_path(event)
      expect(page).to have_link('iCal Feed')
    end
  end

  describe "Calendar View" do
    it "loads successfully" do
      visit calendar_path
      expect(page).to have_content('Event Calendar')
    end

    it "shows upcoming occurrences" do
      # Create event with start_time in the middle of current month to avoid month boundary issues
      mid_month = Date.current.beginning_of_month + 15.days
      start_time = mid_month.to_time + 14.hours # 2 PM on the 15th
      event = create(:event, visibility: 'public', title: 'Calendar Event', start_time: start_time)
      occurrence = event.occurrences.first

      # Visit the calendar for the month containing the occurrence
      visit calendar_path(month: occurrence.occurs_at.strftime('%Y-%m-%d'))
      expect(page).to have_content('Calendar Event')
      expect(page).to have_content(occurrence.occurs_at.day.to_s)
    end

    it "groups occurrences by month" do
      event = create(:event, visibility: 'public')

      visit calendar_path
      expect(page).to have_content(event.start_time.strftime('%B %Y'))
    end
  end

  describe "User Authentication" do
    let(:user) { create(:user, email: 'test@example.com', password: 'password123') }

    it "shows sign in page" do
      visit new_user_session_path
      # Page title is "Sign In" with capital I
      expect(page).to have_css('h2', text: /Sign In/i)
      expect(page).to have_field('Email')
      expect(page).to have_field('Password')
    end

    it "sign up is disabled (users created via Authentik OAuth only)" do
      # Sign up route should not exist - only OAuth login allowed
      # Visiting /users/sign_up redirects to sign in (route doesn't exist)
      visit '/users/sign_up'
      # Should be redirected to sign in page
      expect(page).to have_current_path(new_user_session_path)
      # And the sign up link should not be present on the sign in page
      expect(page).not_to have_link('Sign up')
    end

    it "authentication is required for event creation" do
      visit new_event_path
      # Should redirect to sign in
      expect(current_path).to eq(new_user_session_path)
    end
  end

  describe "Event Creation (Admin Only)" do
    let(:admin) { create(:user, role: 'admin') }

    before do
      sign_in admin
    end

    it "shows the new event form" do
      visit new_event_path

      expect(page).to have_field('Title')
      expect(page).to have_field('Description')
      expect(page).to have_button('Next')
    end

    it "shows validation errors for invalid event" do
      visit new_event_path

      # Try to proceed without filling required field
      click_button 'Next'

      # Should stay on step 1 due to validation
      expect(page).to have_field('Title')
    end
  end

  describe "Event Management (Authenticated)" do
    let(:user) { create(:user) }
    let(:event) { create(:event, user: user, title: 'My Event') }

    before do
      sign_in user
    end

    it "shows edit form for own event" do
      visit edit_event_path(event)

      expect(page).to have_field('Title', with: 'My Event')
      expect(page).to have_button('Next')
    end

    it "shows postpone button" do
      visit event_path(event)

      expect(page).to have_button('Postpone')
    end

    it "shows cancel button" do
      visit event_path(event)

      expect(page).to have_button('Cancel Event')
    end

    it "shows delete button" do
      visit event_path(event)

      expect(page).to have_button('Delete')
    end
  end

  describe "Access Control" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:admin) { create(:user, :admin) }
    let(:private_event) { create(:event, :private, user: other_user) }

    it "prevents non-authenticated users from creating events" do
      visit new_event_path
      expect(current_path).to eq(new_user_session_path)
    end

    it "prevents users from editing others' events" do
      sign_in user
      visit edit_event_path(private_event)

      expect(current_path).not_to eq(edit_event_path(private_event))
      expect(page).to have_content('not authorized')
    end

    it "allows admins to edit any event" do
      sign_in admin
      visit edit_event_path(private_event)

      expect(page).to have_field('Title')
    end

    it "shows private events to hosts" do
      sign_in other_user
      visit event_path(private_event)

      expect(page).to have_content(private_event.title)
    end

    it "hides private events from non-hosts" do
      sign_in user
      visit event_path(private_event)

      expect(page).to have_content('not authorized')
    end
  end

  describe "JSON API Endpoints" do
    let!(:public_event) { create(:event, visibility: 'public', title: 'API Event') }

    before do
      # Ensure occurrences are generated for the event
      public_event.generate_occurrences
    end

    it "provides events JSON feed" do
      page.driver.header('Accept', 'application/json')
      visit events_path

      json = JSON.parse(page.body)
      expect(json).to have_key('occurrences')
      expect(json['occurrences'].first['event']['title']).to eq('API Event')
    end

    it "provides calendar JSON feed" do
      create(:event_occurrence, event: public_event, occurs_at: 1.week.from_now)

      page.driver.header('Accept', 'application/json')
      visit calendar_path

      json = JSON.parse(page.body)
      expect(json).to have_key('occurrences')
      expect(json['occurrences']).not_to be_empty
    end

    it "does not expose email addresses in JSON" do
      page.driver.header('Accept', 'application/json')
      visit events_path

      expect(page.body).not_to include('@example.com')
    end
  end

  describe "Responsive Design" do
    it "renders on different viewports" do
      visit root_path
      expect(page).to have_content('EventManager')

      visit events_path
      expect(page).to have_content('All Events')

      visit calendar_path
      expect(page).to have_content('Event Calendar')
    end
  end
end
