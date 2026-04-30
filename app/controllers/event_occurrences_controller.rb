class EventOccurrencesController < ApplicationController # rubocop:disable Metrics/ClassLength
  include ReminderMessageBuilder

  before_action :set_occurrence, only: %i[show edit update destroy postpone cancel relocate reactivate
                                          post_slack_reminder post_social_reminder generate_ai_reminder
                                          send_host_reminder ical]
  before_action :authorize_occurrence, only: %i[edit update destroy postpone cancel relocate reactivate
                                                post_slack_reminder post_social_reminder generate_ai_reminder]
  before_action :authorize_admin, only: %i[send_host_reminder]

  def show
    @event = @occurrence.event
  end

  # Generate iCal file for a single occurrence (for Apple Calendar, etc.)
  def ical
    event = @occurrence.event
    cal = Icalendar::Calendar.new

    cal.event do |e|
      e.dtstart = Icalendar::Values::DateTime.new(@occurrence.occurs_at.utc)
      e.dtend = Icalendar::Values::DateTime.new((@occurrence.occurs_at + @occurrence.duration.minutes).utc)
      e.summary = event.title
      e.description = build_ical_description(event, @occurrence)
      e.location = @occurrence.event_location&.name
      e.url = event_occurrence_url(@occurrence)
      e.uid = "occurrence-#{@occurrence.id}@#{request.host}"
    end

    send_data cal.to_ical,
              type: 'text/calendar',
              disposition: 'attachment',
              filename: "#{event.title.parameterize}-#{@occurrence.occurs_at.strftime('%Y-%m-%d')}.ics"
  end

  def edit
    @event = @occurrence.event
  end

  def update
    @occurrence.current_user_for_journal = current_user

    # Handle banner image removal
    if params[:event_occurrence][:remove_banner_image] == '1'
      EventJournal.log_occurrence_change(
        @occurrence,
        current_user,
        'banner_removed',
        { 'banner_image' => { 'action' => 'removed' } }
      )
      @occurrence.banner_image.purge
    end

    if @occurrence.update(occurrence_params)
      redirect_to @occurrence, notice: 'Occurrence was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @event = @occurrence.event
    @occurrence.destroy
    redirect_to @event, notice: 'Occurrence was successfully deleted.'
  end

  def postpone
    postponed_until = params[:postponed_until] ? Time.zone.parse(params[:postponed_until]) : 1.week.from_now
    if @occurrence.postpone!(postponed_until, params[:reason], current_user)
      redirect_back_or_to @occurrence.event, notice: 'Occurrence was postponed. A new occurrence has been created at the rescheduled date.'
    else
      redirect_back_or_to @occurrence, alert: 'Failed to postpone occurrence.'
    end
  end

  def cancel
    if @occurrence.cancel!(params[:reason], current_user)
      redirect_to @occurrence, notice: 'Occurrence was cancelled.'
    else
      redirect_to @occurrence, alert: 'Failed to cancel occurrence.'
    end
  end

  def relocate
    if params[:relocated_to].blank?
      redirect_to @occurrence, alert: 'New location is required.'
      return
    end

    if @occurrence.relocate!(params[:relocated_to], params[:reason], current_user)
      redirect_to @occurrence, notice: 'Occurrence was marked as relocated.'
    else
      redirect_to @occurrence, alert: 'Failed to mark occurrence as relocated.'
    end
  end

  def reactivate
    if @occurrence.reactivate!(current_user)
      redirect_to @occurrence, notice: 'Occurrence was reactivated.'
    else
      redirect_to @occurrence, alert: 'Failed to reactivate occurrence.'
    end
  end

  def post_slack_reminder
    site_config = SiteConfig.current
    unless site_config.slack_enabled? && @occurrence.event.slack_announce?
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: 'Slack reminders are disabled for this occurrence.' }
        format.json { render json: { success: false, message: 'Slack reminders are disabled for this occurrence.' } }
      end
      return
    end

    label = timing_label_for(@occurrence)
    message = long_reminder_message(@occurrence, label)
    if SlackService.post_occurrence_reminder(@occurrence, message)
      respond_to do |format|
        format.html { redirect_to @occurrence, notice: 'Posted reminder to Slack.' }
        format.json { render json: { success: true, message: 'Posted reminder to Slack.' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: 'Failed to post to Slack.' }
        format.json { render json: { success: false, message: 'Failed to post to Slack.' } }
      end
    end
  end

  def post_social_reminder
    site_config = SiteConfig.current
    unless site_config.social_reminders_enabled? && @occurrence.event.social_reminders?
      Rails.logger.info "post_social_reminder: Disabled - site=#{site_config.social_reminders_enabled?}, event=#{@occurrence.event.social_reminders?}"
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: 'Social reminders are disabled for this occurrence.' }
        format.json { render json: { success: false, message: 'Social reminders are disabled for this occurrence.' } }
      end
      return
    end

    Rails.logger.info "post_social_reminder: Posting for occurrence #{@occurrence.id} (#{@occurrence.event.title})"
    label = timing_label_for(@occurrence)
    short_parts = reminder_message_with_link(@occurrence, label, message_type: :short)
    long_parts = reminder_message_with_link(@occurrence, label, message_type: :long)
    if SocialService.post_occurrence_reminder(@occurrence, short_parts: short_parts, long_parts: long_parts)
      respond_to do |format|
        format.html { redirect_to @occurrence, notice: 'Posted reminder to social media.' }
        format.json { render json: { success: true, message: 'Posted reminder to social media.' } }
      end
    else
      Rails.logger.warn "post_social_reminder: SocialService.post_occurrence_reminder returned false"
      error_msg = 'Failed to post to social media. Check that credentials are configured.'
      respond_to do |format|
        format.html { redirect_to @occurrence, alert: error_msg }
        format.json { render json: { success: false, message: error_msg } }
      end
    end
  end

  def generate_ai_reminder
    days_ahead = params[:days].to_i
    days_ahead = 6 unless [1, 6].include?(days_ahead)
    message_type = params[:type]&.to_sym || :short

    unless OllamaService.configured?
      render json: { success: false, message: 'AI server not configured.' }
      return
    end

    generated_text = if message_type == :long
                       OllamaService.generate_long_reminder(@occurrence, days_ahead)
                     else
                       OllamaService.generate_short_reminder(@occurrence, days_ahead)
                     end

    if generated_text.present?
      render json: { success: true, message: generated_text }
    else
      render json: { success: false, message: 'Failed to generate AI reminder. Check server logs.' }
    end
  end

  def send_host_reminder
    site_config = SiteConfig.current
    @event = @occurrence.event

    return redirect_to @occurrence, alert: 'Host email reminders are disabled.' unless site_config.host_email_reminders_enabled?

    hosts = @event.hosts.where(email_reminders_enabled: true)
    return redirect_to @occurrence, alert: 'No hosts with email reminders enabled.' if hosts.empty?

    reminder_type = determine_reminder_type(@event, site_config)
    days_until = (@occurrence.occurs_at.to_date - Date.current).to_i
    test_email = site_config.email_test_mode_enabled? ? site_config.email_test_mode_address : nil

    hosts.each do |host|
      HostReminderMailer.upcoming_reminder_notification(
        user: host, occurrence: @occurrence, reminder_type: reminder_type,
        days_until_event: days_until, recipient_email: test_email || host.email
      ).deliver_now
    end

    notice = "Host reminder sent to #{hosts.count} #{'host'.pluralize(hosts.count)}"
    notice += " (test mode: #{test_email})" if test_email.present?
    redirect_to @occurrence, notice: notice
  end

  private

  def set_occurrence
    @occurrence = EventOccurrence.friendly_find(params[:id])
  end

  def authorize_occurrence
    @event = @occurrence.event
    return if current_user && (current_user.admin? || @event.hosted_by?(current_user))

    redirect_to @occurrence, alert: "You are not authorized to manage this occurrence."
  end

  def authorize_admin
    return if current_user&.admin?

    redirect_to @occurrence, alert: "You must be an admin to perform this action."
  end

  def occurrence_params
    p = params.expect(event_occurrence: %i[occurs_at custom_description duration_override status banner_image
                                           location_id
                                           reminder_7d_short reminder_1d_short
                                           reminder_7d_long reminder_1d_long])
    return p if p[:occurs_at].blank?

    p.merge(occurs_at: Time.zone.parse(p[:occurs_at].to_s))
  end

  def build_ical_description(event, occurrence)
    parts = []
    parts << occurrence.description if occurrence.description.present?
    parts << "More info: #{event.more_info_url}" if event.more_info_url.present?
    parts << "Event page: #{event_occurrence_url(occurrence)}"
    parts.join("\n\n")
  end

  def determine_reminder_type(event, site_config)
    return 'slack' if event.slack_announce? && site_config.slack_enabled?
    return 'social' if event.social_reminders? && site_config.social_reminders_enabled?

    'general'
  end

  def timing_label_for(occurrence)
    days_until = (occurrence.occurs_at.to_date - Date.current).to_i

    case days_until
    when ..(-1) then 'recently' # Past event
    when 0 then 'today'
    when 1 then 'tomorrow'
    when 2..6 then "#{days_until} days"
    when 7 then '1 week'
    else "#{days_until} days"
    end
  end
end
