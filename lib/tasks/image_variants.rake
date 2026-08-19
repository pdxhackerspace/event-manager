namespace :images do
  desc 'Generate preview variants for event images uploaded before variants were preprocessed'
  task preprocess_variants: :environment do
    images = EventImage.joins(image_attachment: :blob)
    total = images.count
    generated = 0
    skipped = 0
    failed = 0

    puts "Found #{total} event images with attachments"

    images.find_each.with_index do |event_image, index|
      attachment = event_image.image
      puts "[#{index + 1}/#{total}] Event ##{event_image.event_id} image ##{event_image.id}"

      unless attachment.variable?
        puts '  - Skipped (not a transformable image)'
        skipped += 1
        next
      end

      EventImage::PREVIEW_VARIANTS.each_key do |variant_name|
        attachment.variant(variant_name).processed
        puts "  ✓ Generated :#{variant_name}"
        generated += 1
      rescue StandardError => e
        puts "  ✗ Failed :#{variant_name}: #{e.message}"
        failed += 1
      end
    end

    puts "\nDone! Generated #{generated} variants, skipped #{skipped} images, #{failed} failures."
  end
end
