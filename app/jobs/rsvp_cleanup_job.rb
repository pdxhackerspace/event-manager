class RsvpCleanupJob < ApplicationJob
  queue_as :default

  def perform
    RsvpLifecycle.purge_pending!
    RsvpLifecycle.finalize_checkins!
    RsvpLifecycle.anonymize_guests!
  end
end
