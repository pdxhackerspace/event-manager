# frozen_string_literal: true

# Helper module for schedule parsing and description generation
# rubocop:disable-next Metrics/ModuleLength
module EventsHelper
  DAY_NUM_TO_NAME = { 0 => 'sunday', 1 => 'monday', 2 => 'tuesday', 3 => 'wednesday',
                      4 => 'thursday', 5 => 'friday', 6 => 'saturday' }.freeze
  OCC_NUM_TO_NAME = { 1 => 'first', 2 => 'second', 3 => 'third', 4 => 'fourth', -1 => 'last' }.freeze

  def schedule_description(event)
    case event.recurrence_type
    when 'once' then event.start_time.strftime('%A, %B %d, %Y')
    when 'weekly' then weekly_schedule_description(event)
    when 'monthly' then monthly_schedule_description(event)
    when 'custom' then custom_schedule_description(event)
    else event.recurrence_type.titleize
    end
  end

  def parse_monthly_recurrence(event)
    return default_monthly_result unless event.persisted? && event.recurrence_type == 'monthly' &&
                                         event.recurrence_rule.present?

    parse_monthly_rule(event)
  rescue StandardError => e
    Rails.logger.error "Error parsing monthly recurrence for event #{event.id}: #{e.message}"
    default_monthly_result
  end

  def parse_weekly_recurrence(event)
    return default_weekly_result unless event.persisted? && event.recurrence_type == 'weekly' &&
                                        event.recurrence_rule.present?

    parse_weekly_rule(event)
  rescue StandardError => e
    Rails.logger.error "Error parsing weekly recurrence for event #{event.id}: #{e.message}"
    default_weekly_result
  end

  private

  def default_monthly_result
    { occurrences: [], except_occurrences: [], day: nil }
  end

  def default_weekly_result
    { days: [], interval: 1 }
  end

  def parse_monthly_rule(event)
    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    rules = schedule.rrules
    return default_monthly_result if rules.empty?

    result = extract_monthly_occurrences(rules.first)
    result[:except_occurrences] = extract_exception_occurrences(schedule)
    result
  end

  def extract_monthly_occurrences(rule)
    raw_day_of_week = rule.validations[:day_of_week]
    return default_monthly_result if raw_day_of_week.blank?

    day_num = nil
    occurrence_nums = []
    raw_day_of_week.each do |validation|
      day_num ||= validation.day if validation.respond_to?(:day)
      occ = validation.instance_variable_get(:@occ)
      occurrence_nums << occ if occ
    end

    return default_monthly_result unless day_num && occurrence_nums.any?

    {
      occurrences: occurrence_nums.map { |num| OCC_NUM_TO_NAME[num] }.compact,
      day: DAY_NUM_TO_NAME[day_num]
    }
  end

  def extract_exception_occurrences(schedule)
    except_rules = schedule.exrules
    return [] if except_rules.empty?

    exception_nums = []
    except_rules.each do |rule|
      raw_day_of_week = rule.validations[:day_of_week]
      next if raw_day_of_week.blank?

      raw_day_of_week.each do |validation|
        occ = validation.instance_variable_get(:@occ)
        exception_nums << occ if occ
      end
    end

    exception_nums.map { |num| OCC_NUM_TO_NAME[num] }.compact
  end

  def parse_weekly_rule(event)
    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    rules = schedule.rrules
    return default_weekly_result if rules.empty?

    rule = rules.first
    day_validations = rule.validations[:day] || []
    days = day_validations.map { |v| v.respond_to?(:day) ? v.day : v }.compact

    # Extract interval from the rule
    interval = extract_weekly_interval(rule)

    { days: days, interval: interval }
  end

  def extract_weekly_interval(rule)
    interval_validation = rule.validations[:interval]&.first
    return 1 unless interval_validation

    interval_validation.instance_variable_get(:@interval) || 1
  end

  def weekly_schedule_description(event)
    parsed = parse_weekly_recurrence(event)
    days = parsed[:days]
    interval = parsed[:interval]

    return "Weekly on #{event.start_time.strftime('%A')}" if days.empty?

    day_names = days.map { |d| Date::DAYNAMES[d] }
    interval_text = interval_description(interval)

    if day_names.length == 1
      "#{interval_text} on #{day_names.first}"
    else
      "#{interval_text} on #{format_list(day_names)}"
    end
  end

  def interval_description(interval)
    case interval
    when 1 then 'Weekly'
    when 2 then 'Every other week'
    else "Every #{interval} weeks"
    end
  end

  def monthly_schedule_description(event)
    parsed = parse_monthly_recurrence(event)
    return monthly_day_of_month_description(event) unless parsed[:day].present? && parsed[:occurrences].any?

    day_name = parsed[:day].titleize
    occ_names = parsed[:occurrences].map(&:titleize)
    base = occ_names.length == 1 ? "#{occ_names.first} #{day_name}s" : "#{format_list(occ_names)} #{day_name}s"

    # Add exception description if present
    if parsed[:except_occurrences].present?
      except_names = parsed[:except_occurrences].map(&:titleize)
      except_text = except_names.length == 1 ? except_names.first : format_list(except_names)
      base += " (except #{except_text})"
    end

    base
  end

  def custom_schedule_description(event)
    return 'Custom schedule' if event.recurrence_rule.blank?

    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    rules = schedule.rrules
    return 'Custom schedule' if rules.empty?

    # Describe each rule
    descriptions = rules.map { |rule| describe_custom_rule(rule) }
    descriptions.join(' and ')
  rescue StandardError
    'Custom schedule'
  end

  def describe_custom_rule(rule)
    case rule.class.name
    when 'IceCube::WeeklyRule'
      describe_weekly_rule(rule)
    when 'IceCube::MonthlyRule'
      describe_monthly_rule(rule)
    else
      'Custom recurrence'
    end
  end

  def describe_weekly_rule(rule)
    interval = extract_weekly_interval(rule)
    day_validations = rule.validations[:day] || []
    days = day_validations.map { |v| v.respond_to?(:day) ? v.day : v }.compact
    day_names = days.map { |d| Date::DAYNAMES[d] }

    interval_text = interval_description(interval)
    if day_names.length == 1
      "#{interval_text} on #{day_names.first}"
    else
      "#{interval_text} on #{format_list(day_names)}"
    end
  end

  def describe_monthly_rule(rule)
    raw_day_of_week = rule.validations[:day_of_week]
    return 'Monthly' if raw_day_of_week.blank?

    day_num = nil
    occurrence_nums = []
    raw_day_of_week.each do |validation|
      day_num ||= validation.day if validation.respond_to?(:day)
      occ = validation.instance_variable_get(:@occ)
      occurrence_nums << occ if occ
    end

    return 'Monthly' unless day_num && occurrence_nums.any?

    day_name = DAY_NUM_TO_NAME[day_num]&.titleize
    occ_names = occurrence_nums.map { |num| OCC_NUM_TO_NAME[num]&.titleize }.compact
    occ_text = occ_names.length == 1 ? occ_names.first : format_list(occ_names)
    "#{occ_text} #{day_name}"
  end

  def monthly_day_of_month_description(event)
    day = event.start_time.day
    suffix = (11..13).include?(day % 100) ? 'th' : { 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(day % 10, 'th')
    "#{day}#{suffix} of each month"
  end

  def format_list(items)
    "#{items[0..-2].join(', ')} and #{items.last}"
  end
end
