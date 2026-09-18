require 'rails_helper'

RSpec.describe Spectra6BannerLookup do
  # Mirrors the blob record Spectra6BannerJob creates. Only the record is needed
  # here: the lookup resolves by key and never reads the file.
  def create_spectra6_variant(attachment)
    ActiveStorage::Blob.create!(
      key: Spectra6BannerJob.variant_key(attachment.blob),
      filename: 'banner-spectra6.png',
      content_type: 'image/png',
      byte_size: 16,
      checksum: Digest::MD5.base64digest('spectra6'),
      service_name: ActiveStorage::Blob.service.name
    )
  end

  let(:event) { create(:event, :with_banner) }
  let(:attachment) { event.reload.fallback_event_image.image }

  describe 'key agreement with the writer' do
    it 'looks under the key Spectra6BannerJob writes to' do
      variant = create_spectra6_variant(attachment)

      # Spectra6BannerJob.variant_key is the only definition of the layout; this
      # asserts the lookup reads from there rather than deriving its own.
      expect(described_class.new([attachment]).blob_for(attachment).key)
        .to eq(Spectra6BannerJob.variant_key(attachment.blob))
      expect(variant.key).to eq(Spectra6BannerJob.variant_key(attachment.blob))
    end
  end

  describe '#blob_for' do
    it 'finds a variant that exists' do
      variant = create_spectra6_variant(attachment)

      expect(described_class.new([attachment]).blob_for(attachment)).to eq(variant)
    end

    it 'returns nil when no variant has been generated' do
      expect(described_class.new([attachment]).blob_for(attachment)).to be_nil
    end

    it 'returns nil for an unattached attachment' do
      unattached = create(:event_image).image

      expect(described_class.new([unattached]).blob_for(unattached)).to be_nil
    end

    it 'returns nil for nil' do
      expect(described_class.new([]).blob_for(nil)).to be_nil
    end
  end

  describe 'query behavior' do
    it 'resolves a batch of attachments with a single query' do
      events = Array.new(4) { create(:event, :with_banner) }
      attachments = events.map { |e| e.reload.fallback_event_image.image }
      attachments.each { |a| create_spectra6_variant(a) }

      lookup = nil
      queries = count_queries { lookup = described_class.new(attachments) }

      expect(queries).to eq(1)
      expect(attachments.map { |a| lookup.blob_for(a) }).to all(be_present)
    end

    it 'issues no query when there are no attached attachments' do
      expect(count_queries { described_class.new([]) }).to eq(0)
    end

    it 'does not query again when resolving' do
      variant = create_spectra6_variant(attachment)
      lookup = described_class.new([attachment])

      expect(count_queries { lookup.blob_for(attachment) }).to eq(0)
      expect(lookup.blob_for(attachment)).to eq(variant)
    end
  end
end
