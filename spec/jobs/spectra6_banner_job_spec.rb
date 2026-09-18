require 'rails_helper'

RSpec.describe Spectra6BannerJob do
  # A real PNG, since the job hands it to ImageMagick.
  def attach_real_image(event_image)
    event_image.image.attach(
      io: Rails.root.join('lib/assets/spectra6_palette.png').open,
      filename: 'banner.png',
      content_type: 'image/png'
    )
    event_image.reload.image.blob
  end

  let(:event) { create(:event) }
  let(:event_image) { create(:event_image, event: event) }

  describe '.variant_key' do
    it 'places the variant in the output subdirectory for a flat key' do
      blob = instance_double(ActiveStorage::Blob, key: 'abc123')

      expect(described_class.variant_key(blob)).to eq("#{described_class::OUTPUT_SUBDIR}/abc123.png")
    end

    it 'does not produce a relative path segment' do
      blob = instance_double(ActiveStorage::Blob, key: 'abc123')

      # "./..." is what Active Storage rejects as path traversal.
      expect(described_class.variant_key(blob)).not_to start_with('.')
    end

    it 'keeps the directory when the original key has one' do
      blob = instance_double(ActiveStorage::Blob, key: 'nested/dir/abc123')

      expect(described_class.variant_key(blob)).to eq("nested/dir/#{described_class::OUTPUT_SUBDIR}/abc123.png")
    end

    it 'replaces the original extension with .png' do
      blob = instance_double(ActiveStorage::Blob, key: 'abc123.jpg')

      expect(described_class.variant_key(blob)).to end_with('/abc123.png')
    end

    it 'produces a key the storage service accepts' do
      blob = instance_double(ActiveStorage::Blob, key: ActiveStorage::Blob.generate_unique_secure_token)

      expect { ActiveStorage::Blob.service.send(:path_for, described_class.variant_key(blob)) }.not_to raise_error
    end
  end

  describe '#perform' do
    it 'creates the variant blob' do
      blob = attach_real_image(event_image)

      expect { described_class.perform_now(blob.id) }
        .to change { ActiveStorage::Blob.exists?(key: described_class.variant_key(blob)) }
        .from(false).to(true)
    end

    it 'stores it as a png' do
      blob = attach_real_image(event_image)

      described_class.perform_now(blob.id)

      variant = ActiveStorage::Blob.find_by(key: described_class.variant_key(blob))
      expect(variant.content_type).to eq('image/png')
      expect(variant.byte_size).to be_positive
    end

    it 'names the variant after the original' do
      blob = attach_real_image(event_image)
      # EventImage#rename_image renames uploads on save, so derive the
      # expectation from the stored name rather than the uploaded one.
      original_name = File.basename(blob.filename.to_s, '.*')

      described_class.perform_now(blob.id)

      variant = ActiveStorage::Blob.find_by(key: described_class.variant_key(blob))
      expect(variant.filename.to_s).to eq("#{original_name}-spectra6.png")
    end

    it 'resizes to the target dimensions' do
      blob = attach_real_image(event_image)

      described_class.perform_now(blob.id)

      variant = ActiveStorage::Blob.find_by(key: described_class.variant_key(blob))
      variant.open do |file|
        dimensions = MiniMagick::Image.open(file.path)
        expect(dimensions.width).to eq(described_class::TARGET_WIDTH)
        expect(dimensions.height).to eq(described_class::TARGET_HEIGHT)
      end
    end

    it 'can be run again for the same original' do
      blob = attach_real_image(event_image)
      described_class.perform_now(blob.id)

      expect { described_class.perform_now(blob.id) }.not_to raise_error

      expect(ActiveStorage::Blob.where(key: described_class.variant_key(blob)).count).to eq(1)
    end

    it 'does nothing for a blob that does not exist' do
      expect { described_class.perform_now(-1) }.not_to raise_error
    end

    it 'does nothing for a blob that is not an attached image' do
      orphan = ActiveStorage::Blob.create_and_upload!(
        io: Rails.root.join('lib/assets/spectra6_palette.png').open,
        filename: 'orphan.png',
        content_type: 'image/png'
      )

      expect { described_class.perform_now(orphan.id) }
        .not_to change(ActiveStorage::Blob, :count)
    end
  end

  describe 'interaction with Spectra6BannerLookup' do
    it 'writes a key the lookup resolves' do
      # The :with_banner factory attaches placeholder bytes, which ImageMagick
      # cannot read, so this needs a real image.
      attach_real_image(event_image)
      attachment = event_image.reload.image

      described_class.perform_now(attachment.blob.id)

      expect(Spectra6BannerLookup.new([attachment]).blob_for(attachment)).to be_present
    end
  end
end
