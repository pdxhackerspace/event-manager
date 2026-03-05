class EventsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:ical]

  before_action :authenticate_user!, except: %i[index show ical embed rss event_rss eink]
  before_action :set_event, only: %i[show embed edit update destroy postpone cancel reactivate generate_ai_reminder event_rss]
  before_action :authorize_event, only: %i[edit update destroy postpone cancel reactivate]

  def index
    @search_query = params[:q]
    @open_to_filter = params[:open_to]

    # Start with policy-scoped events
    base_events = policy_scope(Event).where(status: 'active')

    # Apply search filter if query present
    base_events = base_events.search(@search_query) if @search_query.present?

    # Apply open_to filter if specified
    base_events = base_events.where(open_to: @open_to_filter) if @open_to_filter.present?

    # Get upcoming occurrences for these events (include relocated to show permanently relocated events)
    upcoming_occurrences = EventOccurrence
                           .joins(:event)
                           .where(event: base_events)
                           .where(event_occurrences: { status: %w[active relocated] })
                           .upcoming
                           .includes(event: %i[user hosts])

    # Build a map of event_id => next occurrence for display
    @next_occurrence_by_event = {}
    upcoming_occurrences.each do |occurrence|
      event_id = occurrence.event_id
      next if @next_occurrence_by_event[event_id] # Already have the first (earliest) occurrence

      @next_occurrence_by_event[event_id] = occurrence
    end

    # Get unique events, sorted by next occurrence date
    @events = upcoming_occurrences.map(&:event).uniq.sort_by do |event|
      @next_occurrence_by_event[event.id]&.occurs_at || event.start_time
    end

    respond_to do |format|
      format.html
      format.json { render json: events_json_response }
    end
  end

  def rss
    @events = Event.where(status: 'active', draft: false)
                   .where(visibility: %w[public members])
                   .includes(:user, :hosts, :occurrences)
                   .order(updated_at: :desc)
                   .limit(50)

    respond_to do |format|
      format.rss { render layout: false }
    end
  end

  def event_rss
    # RSS feed for a single event's occurrences
    # Only allow for public/members events that aren't drafts
    if @event.draft? || @event.visibility == 'private'
      head :not_found
      return
    end

    @occurrences = @event.occurrences.upcoming.limit(20)

    respond_to do |format|
      format.rss { render layout: false }
    end
  end

  def eink
    # Minimal JSON feed for e-ink signs
    # Returns only the next 5 occurrences with essential data
    render json: eink_json_response
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
                           .where('occurs_at >= ? OR status IN (?)', Time.now, %w[postponed cancelled])
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
    authorize @event

    # Build IceCube schedule if recurring
    if @event.recurring?
      recurrence_params = build_recurrence_params
      schedule = Event.build_schedule(@event.start_time, @event.recurrence_type, recurrence_params)
      @event.recurrence_rule = schedule.to_yaml
    end

    if @event.save
      # Check for scheduling conflicts
      conflicts = @event.check_conflicts

      if conflicts.any?
        # Build conflict warning message
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

        flash[:conflict] = view_context.safe_join(
          ['Event created successfully, but scheduling conflicts detected with:', view_context.tag.br] + conflict_links,
          view_context.tag.br
        )
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

    # Handle banner image removal
    if params[:event][:remove_banner_image] == '1'
      EventJournal.log_event_change(
        @event,
        current_user,
        'banner_removed',
        { 'banner_image' => { 'action' => 'removed' } }
      )
      @event.banner_image.purge
    end

    # Only rebuild schedule if recurrence settings were explicitly changed
    if should_rebuild_schedule?
      recurrence_params = build_recurrence_params
      new_start_time = params[:event][:start_time].present? ? Time.zone.parse(params[:event][:start_time]) : @event.start_time
      schedule = Event.build_schedule(new_start_time, params[:event][:recurrence_type], recurrence_params)
      @event.recurrence_rule = schedule.to_yaml
    end

    begin
      if @event.update(event_params)
        redirect_to @event, notice: 'Event was successfully updated.'
      else
        Rails.logger.error "Event update failed. Errors: #{@event.errors.full_messages.join(', ')}"
        Rails.logger.error "Event attributes: #{@event.attributes.slice('id', 'title', 'status', 'recurrence_type')}"
        render :edit, status: :unprocessable_content
      end
    rescue StandardError => e
      Rails.logger.error "Event update exception: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise
    end
  end

  def destroy
    @event.destroy
    redirect_to events_url, notice: 'Event was successfully deleted.'
  end

  def postpone
    authorize @event, :postpone?
    postponed_until = params[:postponed_until] ? Time.parse(params[:postponed_until]) : 1.week.from_now
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
    message_type = params[:type] == 'long' ? :long : :short

    message = if message_type == :long
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

  def ical
    @event = Event.find_by!(ical_token: params[:token])

    # Don't include draft events in iCal feeds
    if @event.draft?
      calendar = Icalendar::Calendar.new
      respond_to do |format|
        format.ics { render plain: calendar.to_ical, content_type: 'text/calendar' }
      end
      return
    end

    calendar = Icalendar::Calendar.new

    # Use actual EventOccurrence records (includes status, customizations)
    @event.event_occurrences.upcoming.limit(50).each do |occurrence|
      calendar.event do |e|
        e.dtstart = Icalendar::Values::DateTime.new(occurrence.occurs_at)
        e.dtend = Icalendar::Values::DateTime.new(occurrence.occurs_at + occurrence.duration.minutes)
        e.summary = @event.title
        e.description = occurrence.description # Uses custom or default
        e.status = occurrence.status.upcase # Per-occurrence status

        # Add cancellation reason if present
        e.description += "\n\n#{occurrence.status.titleize}: #{occurrence.cancellation_reason}" if occurrence.cancellation_reason.present?

        # Add postponed info if applicable
        e.description += "\n\nRescheduled to: #{occurrence.postponed_until.strftime('%B %d, %Y at %I:%M %p')}" if occurrence.status == 'postponed' && occurrence.postponed_until

        # Add relocated info if applicable
        e.description += "\n\nNew Location: #{occurrence.relocated_to}" if occurrence.status == 'relocated' && occurrence.relocated_to.present?
      end
    end

    calendar.publish

    respond_to do |format|
      format.ics { render plain: calendar.to_ical, content_type: 'text/calendar' }
    end
  end

  private

  def set_event
    @event = Event.friendly_find(params[:id])
  end

  def authorize_event
    authorize @event
  end

  def event_params
    params.require(:event).permit(:title, :description, :start_time, :duration,
                                  :recurrence_type, :status, :visibility, :open_to,
                                  :more_info_url, :max_occurrences, :banner_image,
                                  :location_id, :requires_mask, :draft, :slack_announce, :social_reminders,
                                  :reminder_7d_short, :reminder_1d_short, :reminder_7d_long, :reminder_1d_long,
                                  :sign_feed, :permanently_cancelled, :default_to_cancelled,
                                  :permanently_relocated, :relocated_to)
  end

  def build_recurrence_params
    recurrence_type = params[:event][:recurrence_type]
    start_time = params[:event][:start_time].present? ? Time.parse(params[:event][:start_time]) : @event&.start_time

    case recurrence_type
    when 'weekly'
      build_weekly_params(start_time)
    when 'monthly'
      build_monthly_params
    when 'custom'
      build_custom_params(start_time)
    else
      {}
    end
  end

  def build_weekly_params(start_time)
    # Allow selecting multiple days and interval
    days = if params[:recurrence_days].present?
             Array(params[:recurrence_days]).map(&:to_i)
           else
             [start_time&.wday || 0]
           end

    interval = params[:recurrence_interval].present? ? params[:recurrence_interval].to_i : 1

    { days: days, interval: interval }
  end

  def build_monthly_params
    {
      occurrences: params[:recurrence_occurrences],
      except_occurrences: params[:recurrence_except_occurrences],
      day: params[:recurrence_day]
    }.compact
  end

  def build_custom_params(start_time)
    # Custom allows combining multiple rule definitions
    custom_rules = []

    # Parse custom rules from params (array of rule definitions)
    if params[:custom_rules].present?
      params[:custom_rules].each do |rule_data|
        rule = parse_custom_rule(rule_data, start_time)
        custom_rules << rule if rule.present?
      end
    end

    { custom_rules: custom_rules }
  end

  def parse_custom_rule(rule_data, start_time)
    case rule_data[:type]
    when 'weekly'
      days = rule_data[:days].present? ? Array(rule_data[:days]).map(&:to_i) : [start_time&.wday || 0]
      interval = rule_data[:interval].present? ? rule_data[:interval].to_i : 1
      week_offset = rule_data[:week_offset].present? ? rule_data[:week_offset].to_i : 0
      { type: 'weekly', days: days, interval: interval, week_offset: week_offset }
    when 'monthly'
      {
        type: 'monthly',
        occurrences: rule_data[:occurrences],
        except_occurrences: rule_data[:except_occurrences],
        day: rule_data[:day]
      }.compact
    end
  end

  def should_rebuild_schedule?
    return false if params[:event][:recurrence_type].blank?

    # Rebuild if recurrence type changed
    return true if params[:event][:recurrence_type] != @event.recurrence_type

    # Rebuild if start time changed (affects schedule for weekly events)
    return true if params[:event][:start_time].present? && Time.parse(params[:event][:start_time]) != @event.start_time

    # Rebuild if weekly options were explicitly provided
    return true if params[:recurrence_days].present? || params[:recurrence_interval].present?

    # Rebuild if monthly options were explicitly provided
    return true if params[:recurrence_occurrences].present? || params[:recurrence_day].present?
    return true if params[:recurrence_except_occurrences].present?

    # Rebuild if custom rules were provided
    return true if params[:custom_rules].present?

    false
  end

  def events_json_response
    now = Time.current

    # Get all upcoming occurrences from published active events
    # Include occurrences that haven't ended yet (in progress or future)
    occurrences = EventOccurrence
                  .joins(:event)
                  .where(events: { draft: false, status: 'active' })
                  .includes(event: [:hosts, :location, { banner_image_attachment: :blob }])
                  .order(occurs_at: :asc)

    # Filter to occurrences that haven't ended yet and build response
    occurrences_data = occurrences.filter_map do |occ|
      # Skip if occurrence has already ended
      next if occ.occurs_at + occ.duration.minutes < now

      build_occurrence_json(occ)
    end

    # Get unique events that have upcoming occurrences
    events_with_occurrences = Event
                              .where(draft: false, status: 'active')
                              .joins(:occurrences)
                              .where('event_occurrences.occurs_at + (events.duration * interval \'1 minute\') > ?', now)
                              .distinct
                              .includes(:hosts, :location, banner_image_attachment: :blob)
                              .order(:title)

    events_data = events_with_occurrences.map do |event|
      build_event_json(event)
    end

    {
      events: events_data,
      occurrences: occurrences_data,
      generated_at: Time.current.iso8601,
      event_count: events_data.count,
      occurrence_count: occurrences_data.count
    }
  end

  def eink_json_response
    now = Time.current

    # Get next 5 upcoming occurrences from published public/members events
    occurrences = EventOccurrence
                  .joins(:event)
                  .where(events: { draft: false, status: 'active' })
                  .where(events: { visibility: %w[public members] })
                  .where('event_occurrences.occurs_at > ?', now)
                  .includes(event: :location)
                  .order(occurs_at: :asc)
                  .limit(5)

    occurrences_data = occurrences.map do |occ|
      event = occ.event
      show_details = event.sign_feed?

      entry = {
        start_time: occ.occurs_at.to_i,
        duration: occ.duration,
        name: show_details ? event.title : 'Private Event',
        open_to: show_details ? event.open_to : nil,
        location: show_details && event.location ? event.location.name : nil
      }

      # Only include status info if not active and showing details
      if show_details
        case occ.status
        when 'cancelled'
          entry[:cancelled] = true
          entry[:reason] = occ.cancellation_reason if occ.cancellation_reason.present?
        when 'postponed'
          entry[:postponed] = true
          entry[:postponed_until] = occ.postponed_until.to_i if occ.postponed_until
        when 'relocated'
          entry[:relocated] = true
          entry[:relocated_to] = occ.relocated_to if occ.relocated_to.present?
          entry[:reason] = occ.cancellation_reason if occ.cancellation_reason.present?
        end
      end

      entry
    end

    {
      updated_at: now.to_i,
      occurrences: occurrences_data
    }
  end

  def build_occurrence_json(occurrence)
    event = occurrence.event
    is_private = event.visibility != 'public'
    now = Time.current
    occurrence_end = occurrence.occurs_at + occurrence.duration.minutes

    {
      id: occurrence.id,
      slug: occurrence.slug,
      occurs_at: occurrence.occurs_at.iso8601,
      occurs_at_unix: occurrence.occurs_at.to_i,
      ends_at_unix: occurrence_end.to_i,
      duration: is_private ? nil : occurrence.duration,
      is_cancelled: occurrence.status == 'cancelled',
      is_postponed: occurrence.status == 'postponed',
      in_progress: now >= occurrence.occurs_at && now < occurrence_end,
      postponed_until: occurrence.postponed_until&.iso8601,
      open_to: is_private ? nil : event.open_to,
      event: build_event_info(event, is_private),
      location: is_private ? nil : occurrence_location(occurrence),
      description: is_private ? nil : occurrence.description,
      banner_url: is_private ? nil : occurrence_banner_url(occurrence),
      spectra6_banner_url: is_private ? nil : occurrence_spectra6_banner_url(occurrence)
    }
  end

  def build_event_json(event)
    is_private = event.visibility != 'public'

    {
      id: event.id,
      slug: event.slug,
      title: is_private ? 'Private Event' : event.title,
      description: is_private ? nil : event.description,
      more_info_url: is_private ? nil : event.more_info_url,
      visibility: event.visibility,
      open_to: is_private ? nil : event.open_to,
      recurrence_type: event.recurrence_type,
      start_time: event.start_time.iso8601,
      duration: is_private ? nil : event.duration,
      requires_mask: is_private ? nil : event.requires_mask,
      hosts: is_private ? [] : event.hosts.map { |h| h.name || h.email },
      location: is_private ? nil : event_location_json(event),
      banner_url: is_private ? nil : event_banner_url(event),
      spectra6_banner_url: is_private ? nil : spectra6_banner_url_for(event.banner_image)
    }
  end

  def event_location_json(event)
    return nil unless event.location

    { id: event.location.id, name: event.location.name }
  end

  def event_banner_url(event)
    return nil unless event.banner_image.attached?

    url_for(event.banner_image)
  end

  def build_event_info(event, is_private)
    if is_private
      {
        id: event.id,
        slug: event.slug,
        title: 'Private Event',
        description: nil,
        more_info_url: nil,
        hosts: [],
        location: nil,
        banner_url: nil,
        spectra6_banner_url: nil
      }
    else
      {
        id: event.id,
        slug: event.slug,
        title: event.title,
        description: event.description,
        more_info_url: event.more_info_url,
        hosts: event.hosts.map { |h| h.name || h.email },
        location: event.location ? { id: event.location.id, name: event.location.name } : nil,
        banner_url: event.banner_image.attached? ? url_for(event.banner_image) : nil,
        spectra6_banner_url: spectra6_banner_url_for(event.banner_image)
      }
    end
  end

  def occurrence_location(occurrence)
    loc = occurrence.event_location
    return nil unless loc

    { id: loc.id, name: loc.name }
  end

  def occurrence_banner_url(occurrence)
    return url_for(occurrence.banner) if occurrence.banner.attached?

    nil
  end

  def occurrence_spectra6_banner_url(occurrence)
    return spectra6_banner_url_for(occurrence.banner) if occurrence.banner.attached?

    # Fall back to event's spectra6 banner
    spectra6_banner_url_for(occurrence.event.banner_image)
  end

  def spectra6_banner_url_for(attachment)
    return nil unless attachment.attached?

    blob = attachment.blob
    spectra6_key = File.join(
      File.dirname(blob.key),
      Spectra6BannerJob::OUTPUT_SUBDIR,
      "#{File.basename(blob.key, '.*')}.png"
    )

    spectra6_blob = ActiveStorage::Blob.find_by(key: spectra6_key)
    return nil unless spectra6_blob

    url_for(spectra6_blob)
  end
end
