# frozen_string_literal: true

class FixDstOccurrenceTimes < ActiveRecord::Migration[7.2]
  def up
    time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]

    fixed_count   = 0
    skipped_count = 0
    error_count   = 0

    Event.unscoped.where.not(recurrence_rule: nil).find_each do |event| # rubocop:disable Metrics/BlockLength
      next if event.recurrence_rule.blank?

      begin
        schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
      rescue StandardError => e
        Rails.logger.warn "FixDstOccurrenceTimes: could not parse schedule for event #{event.id}: #{e.message}"
        error_count += 1
        next
      end

      # Recompute what IceCube *should* produce with timezone-aware boundaries
      begin
        correct_times = schedule.occurrences_between(
          Time.current.in_time_zone(time_zone),
          1.year.from_now.in_time_zone(time_zone)
        ).map do |t|
          local = t.in_time_zone(time_zone)
          time_zone.local(local.year, local.month, local.day,
                          local.hour, local.min, local.sec)
        end
      rescue StandardError => e
        Rails.logger.warn "FixDstOccurrenceTimes: could not compute occurrences for event #{event.id}: #{e.message}"
        error_count += 1
        next
      end

      correct_by_date = correct_times.index_by(&:to_date)

      EventOccurrence.unscoped
                     .where(event_id: event.id)
                     .where('occurs_at > ?', Time.current)
                     .find_each do |occ|
        local_date = occ.occurs_at.in_time_zone(time_zone).to_date
        correct    = correct_by_date[local_date]

        unless correct
          skipped_count += 1
          next
        end

        if occ.occurs_at.utc == correct.utc
          skipped_count += 1
          next
        end

        Rails.logger.info "FixDstOccurrenceTimes: event #{event.id} occurrence #{occ.id} " \
                          "#{occ.occurs_at.in_time_zone(time_zone)} → #{correct}"
        occ.update_column(:occurs_at, correct) # rubocop:disable Rails/SkipsModelValidations
        fixed_count += 1
      end
    end

    Rails.logger.info "FixDstOccurrenceTimes: done. fixed=#{fixed_count} skipped=#{skipped_count} errors=#{error_count}"
    say "Fixed #{fixed_count} occurrences. Skipped #{skipped_count}. Errors: #{error_count}."
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
