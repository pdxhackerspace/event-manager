require 'rails_helper'

RSpec.describe 'Occurrence image assignment', type: :model do
  let(:event) { create(:event) }

  def attach_pool_image(position:)
    create(:event_image, :with_image, event: event, position: position, in_pool: true)
  end

  describe 'on create' do
    it 'assigns the fixed pool image in fixed mode' do
      image = attach_pool_image(position: 0)
      event.update!(image_selection_mode: 'fixed', fixed_event_image_id: image.id)

      occurrence = create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now)

      expect(occurrence.event_image).to eq(image)
      expect(occurrence.custom_event_image?).to be false
    end

    it 'assigns the next cycled image in cycle mode' do
      first = attach_pool_image(position: 0)
      second = attach_pool_image(position: 1)
      event.update!(image_selection_mode: 'cycle', fixed_event_image_id: first.id, image_cycle_index: 1)

      occurrence = create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now)

      expect(occurrence.event_image).to eq(second)
    end

    it 'saves an occurrence built on the event while images cycle' do
      first = attach_pool_image(position: 0)
      attach_pool_image(position: 1)
      event.update!(image_selection_mode: 'cycle', fixed_event_image_id: first.id, image_cycle_index: 0)

      occurrence = event.occurrences.build(occurs_at: 3.weeks.from_now, status: 'active')

      expect { occurrence.save! }.to change { EventOccurrence.where(event_id: event.id).count }.by(1)
      expect(occurrence.reload.event_image).to eq(first)
      expect(event.reload.image_cycle_index).to eq(1)
    end
  end

  describe 'postpone!' do
    it 'assigns a pool image to the replacement occurrence' do
      image = attach_pool_image(position: 0)
      event.update!(image_selection_mode: 'fixed', fixed_event_image_id: image.id)
      event.occurrences.destroy_all
      occurrence = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
      new_date = 2.weeks.from_now

      occurrence.postpone!(new_date)

      replacement = event.occurrences.active.find_by!(occurs_at: new_date)
      expect(replacement.event_image).to eq(image)
    end
  end
end
