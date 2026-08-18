require 'rails_helper'

RSpec.describe 'Active Storage delivery', type: :request do
  let(:event_image) { create(:event_image, :with_image) }

  # Redirect mode cost two requests per image and returned short-lived,
  # uncacheable URLs, so image-heavy pages hammered Puma on every page view.
  it 'serves attachments in a single request' do
    get rails_storage_proxy_path(event_image.image)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('fake image content')
  end

  it 'allows the browser and CDN to cache the response' do
    get rails_storage_proxy_path(event_image.image)

    cache_control = response.headers['Cache-Control']
    expect(cache_control).to include('public')
    expect(cache_control).to match(/max-age=\d{6,}/)
  end

  it 'generates stable URLs that stay cacheable across page loads' do
    first = polymorphic_path(event_image.image)
    second = polymorphic_path(event_image.reload.image)

    expect(first).to eq(second)
    expect(first).to include('/proxy/')
  end
end
