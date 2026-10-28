module SchedulingFlashes
  extend ActiveSupport::Concern

  private

  def prepare_scheduling
    @event.exclusive_actor = current_user
    @event.override_exclusive_conflict = exclusive_override_requested?
  end

  def redirect_after_scheduling_save(notice)
    ExclusiveRequest.new(@event, actor: current_user).notify_review
    result = ScheduleConflictChecker.for_event(@event)
    record_exclusive_override(@event, result.blocks)
    assign_scheduling_flashes(result)
    redirect_to @event, notice: notice
  end

  def assign_scheduling_flashes(result)
    assign_flash(:busy_conflict, SchedulingCopy::CAUTION_INTRO, result.cautions)
    assign_flash(:nearby, SchedulingCopy::NEARBY_INTRO, result.nearby)
  end

  def assign_flash(key, intro, conflicts)
    return if conflicts.empty?

    flash[key] = SchedulingCopy.flash_html(view_context, intro, conflicts)
  end

  def exclusive_override_requested?
    current_user&.admin? && params[:override_exclusive_conflict] == '1'
  end

  def record_exclusive_override(event, blocks)
    return unless exclusive_override_requested?
    return if blocks.empty?

    EventJournal.log_event_change(
      event,
      current_user,
      'exclusive_override',
      { 'overlapped' => blocks.map { |conflict| conflict.event.title }.uniq }
    )
  end
end
