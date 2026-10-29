# Turns the event form's "request no overlap" checkbox into a review status.
# Admins are approved immediately unless the schedule of an approved event changed,
# which sends it back to pending so the new times get reviewed.
class ExclusiveRequest
  def initialize(event, actor:)
    @event = event
    @actor = actor
  end

  def apply(requested)
    if ActiveModel::Type::Boolean.new.cast(requested)
      request_or_reopen
    else
      withdraw
    end
  end

  def notify_review
    return unless @event.exclusive_review_notification
    return unless @event.exclusive_pending?

    ExclusiveRequestMailer.deliver_review_needed(@event)
  end

  def approve!(note: nil)
    decide!('approved', note)
  end

  def deny!(note: nil)
    decide!('denied', note)
  end

  private

  def request_or_reopen
    if @actor&.admin?
      apply_admin_request
    elsif @event.exclusive_approved? && schedule_changing?
      reopen
    elsif !@event.exclusive_pending? && !@event.exclusive_approved?
      mark_pending
    elsif @event.exclusive_pending? && schedule_changing?
      @event.exclusive_review_notification = true
    end
  end

  def apply_admin_request
    if @event.exclusive_approved? && schedule_changing?
      reopen
    elsif !@event.exclusive_approved?
      mark_approved
    end
  end

  def mark_pending
    @event.exclusive_status = 'pending'
    stamp_request
    clear_review
    @event.exclusive_review_notification = true
  end

  def mark_approved
    @event.exclusive_status = 'approved'
    stamp_request
    @event.exclusive_reviewed_by = @actor
    @event.exclusive_reviewed_at = Time.current
    @event.exclusive_review_note = nil
  end

  def reopen
    @event.exclusive_status = 'pending'
    clear_review
    @event.exclusive_review_notification = true
  end

  def withdraw
    return if @event.exclusive_status == 'none'

    @event.exclusive_status = 'none'
    @event.exclusive_review_note = nil
  end

  def stamp_request
    @event.exclusive_requested_by = @actor
    @event.exclusive_requested_at = Time.current
  end

  def clear_review
    @event.exclusive_reviewed_by = nil
    @event.exclusive_reviewed_at = nil
    @event.exclusive_review_note = nil
  end

  def decide!(status, note)
    @event.current_user_for_journal = @actor
    @event.update!(
      exclusive_status: status,
      exclusive_reviewed_by: @actor,
      exclusive_reviewed_at: Time.current,
      exclusive_review_note: note.presence
    )
    ExclusiveRequestMailer.deliver_decision(@event)
  end

  def schedule_changing?
    @event.schedule_fields_changing?
  end
end
