# Builds an unsaved event or occurrence from the scheduling form so the
# conflict notice can update before the form is submitted.
class SchedulingPreview
  def initialize(params, user:)
    @params = params
    @user = user
  end

  def event
    preview = existing_event || @user.events.build
    preview.assign_attributes(event_attributes)
    preview.exclusive_actor = @user
    apply_recurrence(preview)
    apply_exclusive_request(preview)
    preview
  end

  def occurrence_result
    occurrence = EventOccurrence.friendly_find(@params[:occurrence_id])
    starts = @params.dig(:event_occurrence, :occurs_at).presence
    starts_at = starts ? Time.zone.parse(starts) : occurrence.occurs_at
    preview = occurrence.event.occurrences.build(occurs_at: starts_at, status: 'active')
    override = @params.dig(:event_occurrence, :duration_override).presence
    preview.duration_override = override if override
    [occurrence, ScheduleConflictChecker.for_occurrence(preview)]
  end

  def self.event_for(params, user:)
    new(params, user: user).event
  end

  private

  def existing_event
    return if @params[:event_id].blank?

    Event.friendly_find(@params[:event_id])
  end

  def event_attributes
    return {} if @params[:event].blank?

    @params.expect(event: %i[start_time duration recurrence_type busy conflict_buffer_minutes])
  end

  def apply_recurrence(event)
    return if event.start_time.blank?

    if event.recurring?
      recurrence = RecurrenceParams.new(@params, event: event)
      schedule = Event.build_schedule(recurrence.start_time, event.recurrence_type, recurrence.to_h)
      event.recurrence_rule = schedule.to_yaml if schedule
    else
      event.recurrence_rule = nil
    end
  end

  def apply_exclusive_request(event)
    return unless @params[:event]&.key?(:request_exclusive)

    ExclusiveRequest.new(event, actor: @user).apply(@params.dig(:event, :request_exclusive))
  end
end
