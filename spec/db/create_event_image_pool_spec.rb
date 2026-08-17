require 'rails_helper'
require Rails.root.join('db/migrate/20260816180000_create_event_image_pool.rb')

RSpec.describe CreateEventImagePool do
  let(:migration) { described_class.new }

  def attach_legacy_event_banner(event)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('legacy banner'),
      filename: 'legacy-banner.jpg',
      content_type: 'image/jpeg'
    )
    ActiveStorage::Attachment.create!(
      name: 'banner_image',
      record_type: 'Event',
      record_id: event.id,
      blob: blob
    )
  end

  describe '#migrate_event_banners' do
    it 'sets fixed_event_image_id on the event that owned the banner attachment' do
      event = create(:event)
      attach_legacy_event_banner(event)

      migration.send(:migrate_event_banners)

      event.reload
      event_image = event.event_images.pooled.first

      expect(event_image).to be_present
      expect(event.fixed_event_image_id).to eq(event_image.id)
      expect(event.image_selection_mode).to eq('fixed')
      expect(event_image.image).to be_attached
    end
  end
end
