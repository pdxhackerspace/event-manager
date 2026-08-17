class HomeController < ApplicationController
  def index
    # Redirect logged-in users to the dashboard
    redirect_to dashboard_path and return if user_signed_in? && params[:q].blank?

    @site_config = SiteConfig.current
    @search_query = params[:q]

    # Start with policy-scoped events
    base_events = policy_scope(Event).where(status: 'active')

    # Apply search filter if query present
    base_events = base_events.search(@search_query) if @search_query.present?

    # Show ALL upcoming occurrences (no limit) in chronological order
    @upcoming_occurrences = EventOccurrence
                            .joins(:event)
                            .where(event: base_events)
                            .where(event_occurrences: { status: 'active' })
                            .upcoming
                            .includes(event: %i[hosts user location], event_image: { image_attachment: :blob })

    # Build a map of event_id => next occurrence for display
    @next_occurrence_by_event = {}
    @upcoming_occurrences.each do |occurrence|
      event_id = occurrence.event_id
      next if @next_occurrence_by_event[event_id] # Already have the first (earliest) occurrence

      @next_occurrence_by_event[event_id] = occurrence
    end

    # Get unique events from occurrences, sorted by next occurrence date
    @upcoming_events = @upcoming_occurrences.map(&:event).uniq.sort_by do |event|
      @next_occurrence_by_event[event.id]&.occurs_at || event.start_time
    end
  end
end
