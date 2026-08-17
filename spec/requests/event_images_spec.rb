require 'rails_helper'

RSpec.describe 'EventImages', type: :request do
  let(:user) { create(:user, :admin) }
  let(:event) { create(:event, user: user) }
  let!(:first_image) { create(:event_image, :with_image, event: event, position: 0) }
  let!(:second_image) { create(:event_image, :with_image, event: event, position: 1) }

  before do
    event.update!(fixed_event_image_id: first_image.id)
    sign_in user
  end

  describe 'PATCH /events/:event_id/images/reorder' do
    it 'reorders pooled images' do
      patch reorder_event_event_images_path(event),
            params: { ordered_ids: [second_image.id, first_image.id] },
            headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(first_image.reload.position).to eq(1)
      expect(second_image.reload.position).to eq(0)
    end
  end

  describe 'DELETE /events/:event_id/images/:id' do
    it 'removes an image from the pool' do
      expect do
        delete event_event_image_path(event, second_image)
      end.to change { event.event_images.count }.by(-1)

      expect(response).to redirect_to(edit_event_path(event, anchor: 'image-pool'))
    end
  end

  describe 'PATCH /events/:event_id/images/:id' do
    it 'adds an occurrence-only image to the pool' do
      custom_image = create(:event_image, :with_image, :occurrence_only, event: event, position: 2)

      patch event_event_image_path(event, custom_image), params: { event_image: { in_pool: true } }

      expect(response).to redirect_to(edit_event_path(event, anchor: 'image-pool'))
      expect(custom_image.reload.in_pool?).to be true
    end
  end

  describe 'POST /events/:event_id/images/reassign' do
    it 'reassigns non-custom occurrences using the saved selection mode' do
      event.occurrences.destroy_all
      auto_occurrence = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
      custom_occurrence = create(:event_occurrence, :with_banner, event: event, occurs_at: 2.weeks.from_now)
      custom_image = custom_occurrence.event_image

      post reassign_event_event_images_path(event)

      expect(response).to redirect_to(edit_event_path(event, anchor: 'image-pool'))
      expect(flash[:notice]).to include('Reassigned images for 1 occurrence')
      expect(auto_occurrence.reload.event_image).to eq(first_image)
      expect(custom_occurrence.reload.event_image).to eq(custom_image)
    end

    it 'shows an alert when the pool is empty' do
      event.event_images.destroy_all

      post reassign_event_event_images_path(event)

      expect(response).to redirect_to(edit_event_path(event, anchor: 'image-pool'))
      expect(flash[:alert]).to include('No occurrences were reassigned')
    end
  end
end
