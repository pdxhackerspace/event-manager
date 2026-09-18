# Translates the event form's recurrence fields into the options hash
# Event.build_schedule expects, and decides whether a saved event's schedule
# needs rebuilding.
#
# Every value here is coerced through a fixed lookup table or #to_i before it
# reaches Event.build_schedule, and none of it is mass-assigned, so the raw
# params are read directly rather than permitted.
class RecurrenceParams
  OCCURRENCE_DAY_NAMES = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

  def initialize(params, event: nil)
    @params = params
    @event = event
  end

  def recurrence_type
    event_params[:recurrence_type]
  end

  # The time the schedule should anchor on: the submitted start time if the form
  # sent one, otherwise whatever the event already has.
  def start_time
    submitted_start_time || @event&.start_time
  end

  def to_h
    case recurrence_type
    when 'weekly' then weekly_options
    when 'monthly' then monthly_options
    when 'custom' then { custom_rules: custom_rules }
    else {}
    end
  end

  # Only rebuild when the recurrence settings actually changed, so an unrelated
  # edit doesn't regenerate every occurrence.
  def rebuild_schedule?
    return false if recurrence_type.blank?
    return true if recurrence_type != @event&.recurrence_type
    return true if submitted_start_time.present? && submitted_start_time != @event&.start_time

    weekly_fields_submitted? || monthly_fields_submitted? || @params[:custom_rules].present?
  end

  private

  def event_params
    @params[:event] || {}
  end

  def submitted_start_time
    return @submitted_start_time if defined?(@submitted_start_time)

    raw = event_params[:start_time]
    @submitted_start_time = raw.present? ? Time.zone.parse(raw) : nil
  end

  def weekly_fields_submitted?
    @params[:recurrence_days].present? || @params[:recurrence_interval].present?
  end

  def monthly_fields_submitted?
    @params[:recurrence_occurrences].present? ||
      @params[:recurrence_day].present? ||
      @params[:recurrence_except_occurrences].present?
  end

  def weekly_options
    days = if @params[:recurrence_days].present?
             Array(@params[:recurrence_days]).map(&:to_i)
           else
             [start_time&.wday || 0]
           end

    { days: days, interval: interval_from(@params[:recurrence_interval]) }
  end

  def monthly_options
    {
      occurrences: @params[:recurrence_occurrences],
      except_occurrences: @params[:recurrence_except_occurrences],
      day: day_name(@params[:recurrence_day])
    }.compact
  end

  # Custom recurrence combines several rule definitions. The form submits
  # custom_rules[0][...], which Rails parses as a hash keyed by index rather
  # than an array, so accept either shape.
  def custom_rules
    raw = @params[:custom_rules]
    return [] if raw.blank?

    entries = raw.respond_to?(:values) ? raw.values : Array(raw)
    entries.filter_map { |entry| custom_rule(entry) }
  end

  def custom_rule(rule)
    case rule[:type]
    when 'weekly' then custom_weekly_rule(rule)
    when 'monthly' then custom_monthly_rule(rule)
    end
  end

  def custom_weekly_rule(rule)
    days = rule[:days].present? ? Array(rule[:days]).map(&:to_i) : [start_time&.wday || 0]

    {
      type: 'weekly',
      days: days,
      interval: interval_from(rule[:interval]),
      week_offset: rule[:week_offset].to_i
    }
  end

  def custom_monthly_rule(rule)
    {
      type: 'monthly',
      occurrences: rule[:occurrences],
      except_occurrences: rule[:except_occurrences],
      day: day_name(rule[:day])
    }.compact
  end

  def interval_from(value)
    interval = value.to_i
    interval.positive? ? interval : 1
  end

  # Event.build_schedule turns this straight into an IceCube day symbol, so
  # reject anything that isn't a real weekday name.
  def day_name(value)
    return nil if value.blank?

    OCCURRENCE_DAY_NAMES.include?(value.to_s) ? value : nil
  end
end
