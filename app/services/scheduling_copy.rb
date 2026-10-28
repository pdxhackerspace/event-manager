# Sentences shown when a new or edited time overlaps another event.
class SchedulingCopy
  NEARBY_INTRO = 'Nearby events, within 15 minutes. These do not block scheduling:'.freeze
  CAUTION_INTRO = 'Please review these scheduling cautions:'.freeze

  def self.exclusive_block_text(conflicts)
    conflicts.map { |conflict| exclusive_sentence(conflict) }.join(' ')
  end

  def self.exclusive_sentence(conflict)
    "#{conflict.event.title} (#{when_phrase(conflict)}) doesn't allow other events at the same time, " \
      "including #{buffer_phrase(conflict.buffer_minutes)}. Please choose a different time."
  end

  def self.sentence(conflict)
    case conflict.kind
    when :busy then busy_sentence(conflict)
    when :pending_exclusive then pending_sentence(conflict)
    when :reserved_overlap then reserved_sentence(conflict)
    else nearby_sentence(conflict)
    end
  end

  def self.flash_html(view, intro, conflicts)
    lines = conflicts.map do |conflict|
      view.link_to(sentence(conflict), view.event_path(conflict.event), class: 'alert-link')
    end
    view.safe_join([intro, view.tag.br, view.safe_join(lines, view.tag.br)])
  end

  def self.buffer_phrase(minutes)
    minutes = minutes.to_i
    return '0 minutes before and after' if minutes.zero?
    return hour_phrase(minutes / 60) if (minutes % 60).zero?

    "#{minutes} minutes before and after"
  end

  def self.when_phrase(conflict)
    start = conflict.occurrence.occurs_at.in_time_zone
    finish = start + conflict.occurrence.duration.minutes
    "#{start.strftime('%b %d, %I:%M %p')}–#{finish.strftime('%I:%M %p')}"
  end

  def self.busy_sentence(conflict)
    "#{conflict.event.title} (#{when_phrase(conflict)}) is expected to be very busy. " \
      "Your event falls within #{buffer_phrase(conflict.buffer_minutes)}. Consider choosing another time."
  end

  def self.pending_sentence(conflict)
    "#{conflict.event.title} (#{when_phrase(conflict)}) has a pending request to reserve the space, " \
      "including #{buffer_phrase(conflict.buffer_minutes)}. It is not blocked yet, but it may be soon."
  end

  def self.reserved_sentence(conflict)
    "Your no-overlap request would cover #{conflict.event.title} (#{when_phrase(conflict)}), " \
      "including #{buffer_phrase(conflict.buffer_minutes)}. It is not blocked yet. " \
      'An admin will see this overlap when reviewing the request.'
  end

  def self.nearby_sentence(conflict)
    "#{conflict.event.title} (#{when_phrase(conflict)})"
  end

  def self.hour_phrase(hours)
    unit = hours == 1 ? 'hour' : 'hours'
    "#{hours} #{unit} before and after"
  end
  private_class_method :busy_sentence, :pending_sentence, :reserved_sentence, :nearby_sentence, :hour_phrase
end
