class EventImageSelector
  attr_reader :event

  def initialize(event)
    @event = event
  end

  def select(exclude_image_id: nil, use_last_occurrence: true, advance_cycle: true)
    pool = event.event_images.pooled.ordered.to_a
    return nil if pool.empty?

    case event.image_selection_mode
    when 'random'
      last_id = exclude_image_id
      last_id ||= event.occurrences.order(id: :desc).limit(1).pick(:event_image_id) if use_last_occurrence
      select_random(pool, exclude_image_id: last_id)
    when 'cycle'
      select_cycle(pool, advance: advance_cycle)
    else
      event.fallback_event_image
    end
  end

  private

  def select_random(pool, exclude_image_id:)
    return pool.first if pool.size == 1

    candidates = pool.reject { |image| exclude_image_id.present? && image.id == exclude_image_id }
    candidates = pool if candidates.empty?
    candidates.sample
  end

  def select_cycle(pool, advance: true)
    index = event.image_cycle_index % pool.size
    selected = pool[index]
    event.update!(image_cycle_index: event.image_cycle_index + 1) if advance
    selected
  end
end
