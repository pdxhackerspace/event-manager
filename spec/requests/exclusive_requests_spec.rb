require 'rails_helper'

RSpec.describe 'Exclusive requests', :mail, type: :request do
  let(:host) { create(:user, :can_create_events) }
  let(:admin) { create(:user, :admin) }
  let!(:event) do
    create(:event, user: host, title: 'Open House', exclusive_status: 'pending',
                   exclusive_requested_by: host, exclusive_requested_at: Time.current)
  end

  it 'hides the review pages from hosts' do
    sign_in host
    get exclusive_requests_path

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include('not authorized')
  end

  it 'lets an admin approve a request and email the hosts' do
    sign_in admin

    expect do
      post approve_exclusive_request_path(event), params: { note: 'Take the whole space' }
    end.to have_enqueued_mail(ExclusiveRequestMailer, :decision)

    expect(event.reload.exclusive_status).to eq('approved')
    expect(event.exclusive_review_note).to eq('Take the whole space')
    expect(response).to redirect_to(exclusive_requests_path)
  end

  it 'shows overlapping events on the review page' do
    create(:event, title: 'Workshop', start_time: event.start_time, duration: 60)
    sign_in admin

    get exclusive_request_path(event)

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Workshop')
    expect(response.body).to include('Open House')
  end
end
