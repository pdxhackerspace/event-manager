class EventImageReassigner
  attr_reader :event

  def initialize(event)
    @event = event
  end

  def reassign!
    return 0 if event.event_images.pooled.none?

    selector = EventImageSelector.new(event)
    last_image_id = nil
    updated = 0

    reassignable_occurrences.each do |occurrence|
      image = selector.select(exclude_image_id: last_image_id, use_last_occurrence: false)
      next unless image

      occurrence.update!(event_image: image, custom_event_image: false)
      last_image_id = image.id
      updated += 1
    end

    updated
  end

  private

  def reassignable_occurrences
    event.occurrences.where(custom_event_image: false).order(:occurs_at, :id)
  end
end
