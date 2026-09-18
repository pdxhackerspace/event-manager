require 'rails_helper'

RSpec.describe Spectra6BannerLookup do
  # Mirrors the blob record Spectra6BannerJob creates. Only the record is needed
  # here: the lookup resolves by key and never reads the file.
  def create_spectra6_variant(attachment)
    ActiveStorage::Blob.create!(
      key: described_class.derived_key(attachment.blob),
      filename: 'banner-spectra6.png',
      content_type: 'image/png',
      byte_size: 16,
      checksum: Digest::MD5.base64digest('spectra6'),
      service_name: ActiveStorage::Blob.service.name
    )
  end

  let(:event) { create(:event, :with_banner) }
  let(:attachment) { event.reload.fallback_event_image.image }

  describe '.derived_key' do
    it 'places the variant beside the original under the job output subdirectory' do
      blob = attachment.blob

      key = described_class.derived_key(blob)

      expect(File.dirname(key)).to eq(File.join(File.dirname(blob.key), Spectra6BannerJob::OUTPUT_SUBDIR))
      expect(File.basename(key)).to eq("#{File.basename(blob.key, '.*')}.png")
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
