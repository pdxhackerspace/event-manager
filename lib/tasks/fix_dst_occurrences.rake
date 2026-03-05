# Helper module for DST occurrence fixing
module DstOccurrenceFixer
  module_function

  def fix_event(event)
    puts "Processing: #{event.title} (ID: #{event.id})"

    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    puts "  Schedule start: #{schedule.start_time.inspect}"

    future_dates = schedule.occurrences_between(Time.current, 1.year.from_now)
                           .first(event.max_occurrences || 5)

    existing_future = event.occurrences.where('occurs_at > ?', Time.current)
    updated_count = fix_occurrence_times(existing_future, future_dates)

    puts "  Updated #{updated_count} occurrences"
    puts ""
  rescue StandardError => e
    puts "  ERROR: #{e.message}"
    puts ""
  end

  def fix_occurrence_times(occurrences, future_dates)
    updated_count = 0

    occurrences.each do |occ|
      occ_date = occ.occurs_at.to_date
      matching_scheduled = future_dates.find { |d| d.to_date == occ_date }
      next unless matching_scheduled

      correct_time = matching_scheduled.in_time_zone(Time.zone)
      current_time = occ.occurs_at.in_time_zone(Time.zone)
      next if current_time.strftime('%H:%M') == correct_time.strftime('%H:%M')

      puts "  Fixing occurrence #{occ.id}: #{occ.occurs_at} -> #{correct_time}"
      # rubocop:disable Rails/SkipsModelValidations
      occ.update_column(:occurs_at, correct_time)
      # rubocop:enable Rails/SkipsModelValidations
      updated_count += 1
    end

    updated_count
  end

  def regenerate_event(event)
    puts "Processing: #{event.title} (ID: #{event.id})"
    event.regenerate_future_occurrences!
    puts "  Regenerated successfully"
  rescue StandardError => e
    puts "  ERROR: #{e.message}"
  end
end

namespace :events do
  desc 'Fix occurrence times for DST by regenerating from IceCube schedules'
  task fix_dst_occurrences: :environment do
    puts "Fixing DST occurrence times..."
    puts "Time zone: #{Time.zone.name}"
    puts ""

    Event.where.not(recurrence_rule: nil).find_each do |event|
      DstOccurrenceFixer.fix_event(event)
    end

    puts "Done!"
  end

  desc 'Regenerate all future occurrences for all events (destructive for active occurrences)'
  task regenerate_all_occurrences: :environment do
    puts "Regenerating all future occurrences..."
    puts "Time zone: #{Time.zone.name}"
    puts ""

    Event.active.not_permanently_cancelled.not_permanently_relocated.find_each do |event|
      DstOccurrenceFixer.regenerate_event(event)
    end

    puts "Done!"
  end
end
