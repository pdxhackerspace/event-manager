require 'rails_helper'

RSpec.describe EventImageSelector do
  let(:event) { create(:event) }

  def attach_pool_image(position: 0)
    create(:event_image, :with_image, event: event, position: position, in_pool: true)
  end

  describe '#select' do
    context 'when the pool is empty' do
      it 'returns nil' do
        expect(described_class.new(event).select).to be_nil
      end
    end

    context 'when mode is fixed' do
      let!(:second_image) { attach_pool_image(position: 1) }

      before do
        attach_pool_image(position: 0)
        event.update!(image_selection_mode: 'fixed', fixed_event_image_id: second_image.id)
      end

      it 'returns the fixed image' do
        expect(described_class.new(event.reload).select).to eq(second_image)
      end
    end

    context 'when mode is cycle' do
      let!(:first_image) { attach_pool_image(position: 0) }
      let!(:second_image) { attach_pool_image(position: 1) }

      before { event.update!(image_selection_mode: 'cycle', image_cycle_index: 0) }

      it 'returns images in order and increments the cycle index' do
        selector = described_class.new(event.reload)

        expect(selector.select).to eq(first_image)
        expect(event.reload.image_cycle_index).to eq(1)
        expect(described_class.new(event.reload).select).to eq(second_image)
      end
    end

    context 'when mode is random' do
      let!(:first_image) { attach_pool_image(position: 0) }
      let!(:second_image) { attach_pool_image(position: 1) }

      before do
        event.update!(image_selection_mode: 'random')
        create(:event_occurrence, event: event, event_image: first_image, occurs_at: 1.week.from_now)
      end

      it 'avoids repeating the previous occurrence image when possible' do
        selected = described_class.new(event.reload).select
        expect(selected).to eq(second_image)
      end

      it 'allows the only image when the pool has one entry' do
        second_image.destroy!
        selected = described_class.new(event.reload).select
        expect(selected).to eq(first_image)
      end
    end
  end
end
