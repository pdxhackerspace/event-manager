# frozen_string_literal: true

namespace :banners do
  desc 'Generate spectra6 versions of all existing banner images'
  task generate_spectra6: :environment do
    puts 'Generating spectra6 versions of all banner images...'

    images_with_attachments = EventImage.joins(image_attachment: :blob)
    total = images_with_attachments.count

    puts "Found #{total} event images with attachments"

    images_with_attachments.find_each.with_index do |event_image, index|
      puts "[#{index + 1}/#{total}] Processing event ##{event_image.event_id} image ##{event_image.id}"

      blob_id = event_image.image.blob.id
      Spectra6BannerJob.perform_later(blob_id)

      puts "  ✓ Queued job for blob #{blob_id}"
    end

    puts "\nDone! Queued #{total} jobs for processing."
    puts 'Jobs will be processed by Sidekiq.'
  end

  desc 'Generate spectra6 versions synchronously (for debugging)'
  task generate_spectra6_sync: :environment do
    puts 'Generating spectra6 versions of all banner images (synchronous)...'

    images_with_attachments = EventImage.joins(image_attachment: :blob)
    total = images_with_attachments.count
    success = 0
    failed = 0

    puts "Found #{total} event images with attachments"

    images_with_attachments.find_each.with_index do |event_image, index|
      puts "[#{index + 1}/#{total}] Processing event ##{event_image.event_id} image ##{event_image.id}"

      blob_id = event_image.image.blob.id

      begin
        Spectra6BannerJob.perform_now(blob_id)
        puts '  ✓ Processed successfully'
        success += 1
      rescue StandardError => e
        puts "  ✗ Failed: #{e.message}"
        failed += 1
      end
    end

    puts "\nDone! Processed #{success} successfully, #{failed} failed."
  end
end
