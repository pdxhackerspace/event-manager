require 'rails_helper'

RSpec.describe EventImage, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:event) }
    it { is_expected.to have_one_attached(:image) }
  end

  describe 'scopes' do
    let(:event) { create(:event) }
    let!(:pooled) { create(:event_image, :with_image, event: event, position: 0, in_pool: true) }
    let!(:custom) { create(:event_image, :with_image, event: event, position: 1, in_pool: false) }

    it 'returns pooled images only' do
      expect(event.event_images.pooled).to contain_exactly(pooled)
    end

    it 'orders by position' do
      third = create(:event_image, event: event, position: 2, in_pool: true)
      expect(event.event_images.ordered).to eq([pooled, custom, third])
    end
  end
end
