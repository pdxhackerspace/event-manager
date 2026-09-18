# frozen_string_literal: true

class Spectra6BannerJob < ApplicationJob
  queue_as :default

  PALETTE_PATH = Rails.root.join('lib/assets/spectra6_palette.png').freeze
  OUTPUT_SUBDIR = 'spectra6-7.3'
  TARGET_WIDTH = 800
  TARGET_HEIGHT = 240

  # Where the processed variant for a given original is stored.
  #
  # The variant goes in a subdirectory beside the original. Active Storage keys
  # are flat by default, so File.dirname returns "." — joining that in produces
  # a "./..." key, which Rails rejects as a path traversal segment. Only include
  # a directory when the original key actually has one.
  def self.variant_key(blob)
    directory = File.dirname(blob.key)
    segments = [
      directory == '.' ? nil : directory,
      OUTPUT_SUBDIR,
      "#{File.basename(blob.key, '.*')}.png"
    ].compact

    File.join(*segments)
  end

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob

    # Find the attachment to get the record
    attachment = ActiveStorage::Attachment.find_by(blob_id: blob_id, name: %w[banner_image image])
    return unless attachment

    process_banner(blob, attachment)
  end

  private

  def process_banner(blob, _attachment)
    # Download the original image to a temp file
    blob.open do |input_file|
      output_file = Tempfile.new(['spectra6', '.png'])
      begin
        run_imagemagick(input_file.path, output_file.path)

        spectra6_key = self.class.variant_key(blob)

        # Blob keys are unique, so a regenerated variant has to replace the
        # previous one. Lets banners:generate_spectra6 be re-run safely.
        ActiveStorage::Blob.find_by(key: spectra6_key)&.purge

        output_file.rewind
        spectra6_blob = ActiveStorage::Blob.create_and_upload!(
          io: output_file,
          filename: "#{File.basename(blob.filename.to_s, '.*')}-spectra6.png",
          content_type: 'image/png',
          key: spectra6_key
        )

        Rails.logger.info "Spectra6BannerJob: Created spectra6 version for blob #{blob.id} at key #{spectra6_key}"
        spectra6_blob
      ensure
        output_file.close
        output_file.unlink
      end
    end
  rescue StandardError => e
    Rails.logger.error "Spectra6BannerJob: Failed to process blob #{blob.id}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end

  def run_imagemagick(input_path, output_path)
    # Build the ImageMagick command
    # Use resize with ^ to fill the target size (may overflow), then crop to exact dimensions
    command = [
      'magick',
      input_path,
      '-resize', "#{TARGET_WIDTH}x#{TARGET_HEIGHT}^",  # Fill target (may overflow)
      '-gravity', 'center',
      '-extent', "#{TARGET_WIDTH}x#{TARGET_HEIGHT}",   # Crop to exact size
      '-contrast-stretch', '2%x2%',
      '-ordered-dither', 'o8x8',
      '-remap', PALETTE_PATH.to_s,
      "PNG24:#{output_path}"
    ]

    Rails.logger.info "Spectra6BannerJob: Running: #{command.join(' ')}"

    result = system(*command)
    raise "ImageMagick command failed: #{command.join(' ')}" unless result
  end
end
