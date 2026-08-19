require 'rails_helper'

RSpec.describe EventImagesHelper, type: :helper do
  let(:event) { create(:event) }
  let(:event_image) { create(:event_image, :with_image, event: event) }

  describe '#event_image_thumbnail_tag' do
    it 'returns nil when nothing is attached' do
      expect(helper.event_image_thumbnail_tag(EventImage.new.image)).to be_nil
    end

    it 'serves a variant rather than the original blob' do
      tag = helper.event_image_thumbnail_tag(event_image.image)

      expect(tag).to include('/rails/active_storage/representations/')
      expect(tag).not_to include('/rails/active_storage/blobs/')
    end

    it 'defers loading until the image is needed' do
      expect(helper.event_image_thumbnail_tag(event_image.image)).to include('loading="lazy"')
    end

    it 'passes through caller options' do
      tag = helper.event_image_thumbnail_tag(event_image.image, class: 'img-thumbnail', alt: 'Pool image')

      expect(tag).to include('class="img-thumbnail"')
      expect(tag).to include('alt="Pool image"')
    end

    it 'lets the caller override lazy loading' do
      expect(helper.event_image_thumbnail_tag(event_image.image, loading: 'eager')).to include('loading="eager"')
    end
  end

  describe '#event_image_card_tag' do
    it 'serves the larger card variant' do
      thumb = helper.event_image_variant(event_image.image, :thumb)
      card = helper.event_image_variant(event_image.image, :card)

      expect(card.variation.transformations).not_to eq(thumb.variation.transformations)
      expect(helper.event_image_card_tag(event_image.image)).to include('/rails/active_storage/representations/')
    end
  end

  describe '#event_image_variant' do
    it 'falls back to the original for blobs that cannot be transformed' do
      event_image.image.blob.update!(content_type: 'application/pdf')

      expect(helper.event_image_variant(event_image.image, :thumb)).to eq(event_image.image)
    end
  end

  describe 'variant delivery' do
    it 'uses proxy URLs so responses are cacheable by the browser and CDN' do
      expect(helper.event_image_thumbnail_tag(event_image.image)).to include('/representations/proxy/')
    end
  end
end
