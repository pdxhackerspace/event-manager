class EventsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show embed]
  before_action :set_event, only: %i[show embed edit update destroy postpone cancel reactivate generate_ai_reminder]
  before_action :authorize_event, only: %i[edit update destroy postpone cancel reactivate]

  def index
    @search_query = params[:q]
    @open_to_filter = params[:open_to]
    now = Time.current

    # The JSON feed answers a different question than the HTML listing, so it
    # skips the paginated page load entirely.
    respond_to do |format|
      format.html { load_event_page(now) }
      format.json { render json: EventsFeedSerializer.new(url_for: method(:url_for), now: now).as_json }
    end
  end

  def show
    authorize @event
  end

  def embed
    # Public embed view for event calendar
    # Don't allow embedding draft events
    if @event.draft?
      head :forbidden
      return
    end

    # Only show for public events or if user is authorized
    unless @event.public? || (current_user && (current_user.admin? || @event.hosted_by?(current_user)))
      head :forbidden
      return
    end

    @view = params[:view] || 'calendar' # Default to calendar view

    if @view == 'calendar'
      # Get occurrences for display in calendar
      @current_month = params[:month] ? Date.parse(params[:month]) : @event.start_time.to_date.beginning_of_month
      month_start = @current_month.beginning_of_month
      month_end = @current_month.end_of_month

      @occurrences = @event.occurrences
                           .where('occurs_at >= ? AND occurs_at <= ?', month_start, month_end)
                           .where(status: %w[active postponed cancelled])
                           .order(:occurs_at)

      @occurrences_by_date = @occurrences.group_by { |occ| occ.occurs_at.to_date }
    else
      # List view
      @occurrences = @event.occurrences
                           .where('occurs_at >= ? OR status IN (?)', Time.current, %w[postponed cancelled])
                           .order(:occurs_at)
                           .limit(50)

      @occurrences_by_month = @occurrences.group_by { |occ| occ.occurs_at.beginning_of_month }
    end

    render layout: 'embed'
  end

  def new
    @event = current_user.events.build
    authorize @event
  end

  def edit; end

  def create
    @event = current_user.events.build(event_params)
    @event.current_user_for_journal = current_user
    @event.pool_images = params.dig(:event, :pool_images)
    authorize @event

    if @event.recurring?
      schedule = Event.build_schedule(@event.start_time, @event.recurrence_type, recurrence_params.to_h)
      @event.recurrence_rule = schedule.to_yaml
    end

    if @event.save
      conflicts = @event.check_conflicts

      if conflicts.any?
        flash[:conflict] = conflict_warning(conflicts)
        redirect_to @event
      else
        redirect_to @event, notice: 'Event was successfully created.'
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @event.current_user_for_journal = current_user
    @event.pool_images = params.dig(:event, :pool_images)

    if recurrence_params.rebuild_schedule?
      schedule = Event.build_schedule(recurrence_params.start_time, recurrence_params.recurrence_type, recurrence_params.to_h)
      @event.recurrence_rule = schedule.to_yaml
    end

    if @event.update(event_params)
      log_added_pool_images
      redirect_to @event, notice: 'Event was successfully updated.'
    else
      Rails.logger.error "Event update failed. Errors: #{@event.errors.full_messages.join(', ')}"
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @event.destroy
    redirect_to events_url, notice: 'Event was successfully deleted.'
  end

  def postpone
    authorize @event, :postpone?
    postponed_until = params[:postponed_until] ? Time.zone.parse(params[:postponed_until]) : 1.week.from_now
    if @event.postpone!(postponed_until, params[:reason])
      redirect_to @event, notice: 'Event was postponed.'
    else
      redirect_to @event, alert: 'Failed to postpone event.'
    end
  end

  def cancel
    authorize @event, :cancel?
    if @event.cancel!(params[:reason])
      redirect_to @event, notice: 'Event was cancelled.'
    else
      redirect_to @event, alert: 'Failed to cancel event.'
    end
  end

  def reactivate
    authorize @event, :reactivate?
    if @event.reactivate!
      redirect_to @event, notice: 'Event was reactivated.'
    else
      redirect_to @event, alert: 'Failed to reactivate event.'
    end
  end

  def generate_ai_reminder
    authorize @event, :update?

    unless OllamaService.configured?
      render json: { success: false, message: 'AI generation is not configured.' }, status: :service_unavailable
      return
    end

    days = params[:days].to_i
    days = 6 unless [1, 6].include?(days)

    message = if params[:type] == 'long'
                OllamaService.generate_long_reminder_for_event(@event, days)
              else
                OllamaService.generate_short_reminder_for_event(@event, days)
              end

    if message.present?
      render json: { success: true, message: message }
    else
      render json: { success: false, message: 'AI generation failed. Please try again.' }, status: :unprocessable_content
    end
  end

  private

  def set_event
    @event = Event.friendly_find(params[:id])
  end

  def authorize_event
    authorize @event
  end

  def recurrence_params
    @recurrence_params ||= RecurrenceParams.new(params, event: @event)
  end

  def load_event_page(now)
    @pagy, @events = pagy(filtered_events.by_next_occurrence(now).preload(:user, :hosts, :location))
    @next_occurrence_by_event = next_occurrence_by_event(@events, now)
  end

  def filtered_events
    events = policy_scope(Event).where(status: 'active')
    events = events.search(@search_query) if @search_query.present?
    events = events.where(open_to: @open_to_filter) if @open_to_filter.present?
    events
  end

  # The next occurrence for each event on the current page, for the card display.
  # DISTINCT ON keeps this to one row per event instead of every future occurrence.
  def next_occurrence_by_event(events, now)
    return {} if events.empty?

    EventOccurrence.next_per_event(now)
                   .where(event_id: events.map(&:id))
                   .index_by(&:event_id)
  end

  # Uploads picked in the image pool but never submitted through "Add to Pool"
  # ride along with the event form, and the model attaches them during the save.
  def log_added_pool_images
    count = @event.pool_images_attached_count.to_i
    return if count.zero?

    EventJournal.log_event_change(@event, current_user, 'images_added', { 'count' => count })
  end

  def conflict_warning(conflicts)
    conflict_links = conflicts.map do |conflict|
      event = conflict[:event]
      occ = conflict[:occurrence]
      location_text = event.location ? " at #{event.location.name}" : ""

      view_context.link_to(
        "#{event.title} (#{occ.occurs_at.strftime('%B %d at %I:%M %p')}#{location_text})",
        view_context.event_path(event),
        class: 'text-white text-decoration-underline'
      )
    end

    view_context.safe_join(
      ['Event created successfully, but scheduling conflicts detected with:', view_context.tag.br] + conflict_links,
      view_context.tag.br
    )
  end

  def event_params
    params.expect(event: %i[title description start_time duration
                            recurrence_type status visibility open_to
                            more_info_url max_occurrences
                            image_selection_mode fixed_event_image_id
                            location_id requires_mask draft slack_announce social_reminders
                            reminder_7d_short reminder_1d_short reminder_7d_long reminder_1d_long
                            sign_feed permanently_cancelled default_to_cancelled
                            permanently_relocated relocated_to])
  end
end
