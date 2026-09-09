# Helper module for DST occurrence fixing
# rubocop:disable-next Metrics/ModuleLength
module DstOccurrenceFixer
  module_function

  def fix_event(event)
    puts "Processing: #{event.title} (ID: #{event.id})"

    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    expected_hour = schedule.start_time.in_time_zone(Time.zone).hour
    expected_min = schedule.start_time.in_time_zone(Time.zone).min
    puts "  Expected time: #{format('%<hour>02d:%<min>02d', hour: expected_hour, min: expected_min)} local"

    # Get ALL future occurrences, not just ones matching schedule dates
    existing_future = event.occurrences.where('occurs_at > ?', Time.current)
    puts "  Found #{existing_future.count} future occurrences"

    updated_count = 0
    existing_future.find_each do |occ|
      local_time = occ.occurs_at.in_time_zone(Time.zone)
      current_hour = local_time.hour
      current_min = local_time.min

      # Check if the time is off (typically by 1 hour for DST)
      if current_hour != expected_hour || current_min != expected_min
        # Build the correct time: same date, correct hour/minute
        correct_time = local_time.change(hour: expected_hour, min: expected_min)

        puts "  Fixing ##{occ.id}: #{local_time.strftime('%Y-%m-%d %H:%M')} -> #{correct_time.strftime('%H:%M')}"
        # rubocop:disable-next Rails/SkipsModelValidations
        occ.update_column(:occurs_at, correct_time)
        updated_count += 1
      end
    end

    puts "  Updated #{updated_count} occurrences"
    puts ""
  rescue StandardError => e
    puts "  ERROR: #{e.message}"
    puts "  #{e.backtrace.first(3).join("\n  ")}"
    puts ""
  end

  def clean_duplicates(event)
    puts "Processing: #{event.title} (ID: #{event.id})"

    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    expected_hour = schedule.start_time.in_time_zone(Time.zone).hour
    expected_min = schedule.start_time.in_time_zone(Time.zone).min
    puts "  Expected time: #{format('%<hour>02d:%<min>02d', hour: expected_hour, min: expected_min)} local"

    # Group future occurrences by date (ignoring time)
    future_occurrences = event.occurrences.where('occurs_at > ?', Time.current).to_a
    by_date = future_occurrences.group_by { |occ| occ.occurs_at.in_time_zone(Time.zone).to_date }

    duplicates_removed = 0
    by_date.each do |date, occs|
      next unless occs.size > 1

      puts "  Date #{date} has #{occs.size} occurrences:"
      occs.each { |o| puts "    ##{o.id}: #{o.occurs_at.in_time_zone(Time.zone).strftime('%H:%M')} (#{o.status})" }

      # Find the one with correct time, or prefer the newer one if both wrong
      correct_one = occs.find do |o|
        local = o.occurs_at.in_time_zone(Time.zone)
        local.hour == expected_hour && local.min == expected_min
      end
      correct_one ||= occs.max_by(&:id)

      # Delete the others (soft delete if available)
      occs.each do |o|
        next if o.id == correct_one.id

        puts "    Deleting ##{o.id} (keeping ##{correct_one.id})"
        o.destroy
        duplicates_removed += 1
      end
    end

    puts "  Removed #{duplicates_removed} duplicate occurrences"
    puts ""
  rescue StandardError => e
    puts "  ERROR: #{e.message}"
    puts "  #{e.backtrace.first(3).join("\n  ")}"
    puts ""
  end

  def regenerate_event(event)
    puts "Processing: #{event.title} (ID: #{event.id})"
    event.regenerate_future_occurrences!
    puts "  Regenerated successfully"
  rescue StandardError => e
    puts "  ERROR: #{e.message}"
  end

  def debug_events
    puts "Debugging DST occurrence times..."
    puts "Time zone: #{Time.zone.name}"
    puts "Current time: #{Time.current}"
    puts ""

    Event.where.not(recurrence_rule: nil).limit(5).each do |event|
      debug_single_event(event)
    end
  end

  def debug_single_event(event)
    puts "Event: #{event.title} (ID: #{event.id})"

    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    puts "  Schedule start: #{schedule.start_time.inspect}"
    puts "  Schedule start (local): #{schedule.start_time.in_time_zone(Time.zone)}"

    puts "  Future occurrences in DB:"
    event.occurrences.where('occurs_at > ?', Time.current).limit(3).each do |occ|
      local = occ.occurs_at.in_time_zone(Time.zone)
      puts "    ##{occ.id}: #{occ.occurs_at} (UTC) = #{local} (local)"
    end

    puts "  IceCube generates:"
    schedule.occurrences_between(Time.current, 3.months.from_now).first(3).each do |d|
      puts "    #{d.inspect} = #{d.in_time_zone(Time.zone)} (local)"
    end

    puts ""
  end

  def print_header(message)
    puts message
    puts "Time zone: #{Time.zone.name}"
    puts "Current time: #{Time.current}"
    puts ""
  end

  def run_fix_dst
    print_header("Fixing DST occurrence times...")
    Event.where.not(recurrence_rule: nil).find_each { |event| fix_event(event) }
    puts "Done!"
  end

  def run_regenerate_all
    print_header("Regenerating all future occurrences...")
    Event.active.not_permanently_cancelled.not_permanently_relocated.find_each { |event| regenerate_event(event) }
    puts "Done!"
  end

  def run_clean_duplicates
    print_header("Cleaning duplicate occurrences...")
    Event.where.not(recurrence_rule: nil).find_each { |event| clean_duplicates(event) }
    puts "Done!"
  end

  def run_full_fix
    puts "Running full DST fix..."
    puts "=" * 60
    puts ""

    puts "Step 1: Cleaning duplicate occurrences"
    puts "-" * 60
    Event.where.not(recurrence_rule: nil).find_each { |event| clean_duplicates(event) }

    puts ""
    puts "Step 2: Fixing occurrence times"
    puts "-" * 60
    Event.where.not(recurrence_rule: nil).find_each { |event| fix_event(event) }

    puts ""
    puts "=" * 60
    puts "Full DST fix complete!"
  end
end

namespace :events do
  desc 'Fix occurrence times for DST by adjusting to match schedule start time'
  task fix_dst_occurrences: :environment do
    DstOccurrenceFixer.run_fix_dst
  end

  desc 'Regenerate all future occurrences for all events (destructive for active occurrences)'
  task regenerate_all_occurrences: :environment do
    DstOccurrenceFixer.run_regenerate_all
  end

  desc 'Show occurrence times for debugging DST issues'
  task debug_dst: :environment do
    DstOccurrenceFixer.debug_events
  end

  desc 'Remove duplicate occurrences on the same day (keeps the one with correct time)'
  task clean_duplicate_occurrences: :environment do
    DstOccurrenceFixer.run_clean_duplicates
  end

  desc 'Full DST fix: clean duplicates first, then fix times'
  task full_dst_fix: :environment do
    DstOccurrenceFixer.run_full_fix
  end
end
