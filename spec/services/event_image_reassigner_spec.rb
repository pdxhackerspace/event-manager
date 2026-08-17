require 'rails_helper'

RSpec.describe EventImageReassigner do
  let(:event) { create(:event) }

  def attach_pool_image(position:)
    create(:event_image, :with_image, event: event, position: position, in_pool: true)
  end

  describe '#reassign!' do
    it 'returns 0 when the pool is empty' do
      create(:event_occurrence, event: event, occurs_at: 1.week.from_now)

      expect(described_class.new(event).reassign!).to eq(0)
    end

    it 'assigns the fixed image to all non-custom occurrences' do
      image = attach_pool_image(position: 0)
      attach_pool_image(position: 1)
      event.update!(image_selection_mode: 'fixed', fixed_event_image_id: image.id)
      event.occurrences.destroy_all
      first = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
      second = create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now)

      count = described_class.new(event.reload).reassign!

      expect(count).to eq(2)
      expect(first.reload.event_image).to eq(image)
      expect(second.reload.event_image).to eq(image)
    end

    it 'does not change occurrences with custom images' do
      image = attach_pool_image(position: 0)
      event.update!(image_selection_mode: 'fixed', fixed_event_image_id: image.id)
      custom_occurrence = create(:event_occurrence, :with_banner, event: event, occurs_at: 1.week.from_now)
      auto_occurrence = create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now)
      custom_image = custom_occurrence.event_image

      described_class.new(event.reload).reassign!

      expect(custom_occurrence.reload.event_image).to eq(custom_image)
      expect(auto_occurrence.reload.event_image).to eq(image)
    end

    it 'cycles through the pool in chronological order' do
      first = attach_pool_image(position: 0)
      second = attach_pool_image(position: 1)
      event.update!(image_selection_mode: 'cycle', fixed_event_image_id: first.id, image_cycle_index: 0)
      event.occurrences.destroy_all
      occ1 = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
      occ2 = create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now)
      event.update!(image_cycle_index: 0)

      described_class.new(event.reload).reassign!

      expect(occ1.reload.event_image).to eq(first)
      expect(occ2.reload.event_image).to eq(second)
      expect(event.reload.image_cycle_index).to eq(2)
    end

    it 'follows occurs_at order rather than primary key order' do
      first = attach_pool_image(position: 0)
      second = attach_pool_image(position: 1)
      event.update!(image_selection_mode: 'cycle', fixed_event_image_id: first.id, image_cycle_index: 0)
      event.occurrences.destroy_all
      later = create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now)
      earlier = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
      event.update!(image_cycle_index: 0)

      described_class.new(event.reload).reassign!

      expect(earlier.reload.event_image).to eq(first)
      expect(later.reload.event_image).to eq(second)
    end
  end
end
