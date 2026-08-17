class EventImageSelector
  attr_reader :event

  def initialize(event)
    @event = event
  end

  def select
    pool = event.event_images.pooled.ordered.to_a
    return nil if pool.empty?

    case event.image_selection_mode
    when 'random'
      select_random(pool)
    when 'cycle'
      select_cycle(pool)
    else
      event.fallback_event_image
    end
  end

  private

  def select_random(pool)
    return pool.first if pool.size == 1

    last_image_id = event.occurrences.order(id: :desc).limit(1).pick(:event_image_id)
    candidates = pool.reject { |image| image.id == last_image_id }
    candidates = pool if candidates.empty?
    candidates.sample
  end

  def select_cycle(pool)
    index = event.image_cycle_index % pool.size
    selected = pool[index]
    event.update!(image_cycle_index: event.image_cycle_index + 1)
    selected
  end
end
