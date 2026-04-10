class RegenerateEventOccurrencesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "RegenerateEventOccurrencesJob: Starting occurrence regeneration"

    regenerated_count = 0
    error_count = 0

    Event.active.not_permanently_cancelled.not_permanently_relocated.where.not(recurrence_type: 'once').find_each do |event|
      # Count upcoming occurrences
      upcoming_count = event.upcoming_occurrences.count
      target_count = event.max_occurrences || 5

      # Only regenerate if we're running low on future occurrences
      next unless upcoming_count < target_count

      begin
        Rails.logger.info "RegenerateEventOccurrencesJob: Regenerating #{event.title} (#{upcoming_count}/#{target_count})"
        event.regenerate_future_occurrences!
        regenerated_count += 1
      rescue StandardError => e
        Rails.logger.error "RegenerateEventOccurrencesJob: Error regenerating #{event.title}: #{e.message}"
        error_count += 1
      end
    end

    Rails.logger.info "RegenerateEventOccurrencesJob: Completed. Regenerated #{regenerated_count} events, #{error_count} errors"
  end
end
