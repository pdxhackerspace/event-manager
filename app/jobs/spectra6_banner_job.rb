# frozen_string_literal: true

class Spectra6BannerJob < ApplicationJob
  queue_as :default

  PALETTE_PATH = Rails.root.join('lib/assets/spectra6_palette.png').freeze
  OUTPUT_SUBDIR = 'spectra6-7.3'
  TARGET_WIDTH = 800
  TARGET_HEIGHT = 240

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob

    # Find the attachment to get the record
    attachment = ActiveStorage::Attachment.find_by(blob_id: blob_id, name: 'banner_image')
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

        # Upload the processed image with a subdirectory in the key
        original_key = blob.key
        spectra6_key = File.join(File.dirname(original_key), OUTPUT_SUBDIR, "#{File.basename(original_key, '.*')}.png")

        # Create a new blob for the processed image
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
