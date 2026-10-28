class RsvpLogin
  OCCURRENCE_KEY = :rsvp_occurrence_id
  RETURN_KEY = :rsvp_return_to

  def self.remember(controller)
    occurrence_id = controller.params[:rsvp_occurrence_id].presence
    if occurrence_id.blank?
      clear(controller)
      return
    end

    controller.session[OCCURRENCE_KEY] = occurrence_id
    return_to = controller.url_from(controller.params[:return_to])
    if return_to
      controller.session[RETURN_KEY] = return_to
    else
      controller.session.delete(RETURN_KEY)
    end
  end

  def self.finish(controller, user)
    occurrence_id = controller.session.delete(OCCURRENCE_KEY)
    return_to = controller.session.delete(RETURN_KEY)
    return if occurrence_id.blank?

    occurrence = EventOccurrence.find_by(id: occurrence_id)
    destination = return_to.presence || event_destination(controller, occurrence)
    controller.stored_location_for(:user)
    return destination if occurrence.nil?

    outcome = RsvpService.new(occurrence).create(user: user)
    key, message = flash_for(outcome)
    controller.flash[:notice] = nil if key == :alert
    controller.flash[key] = message
    destination || event_destination(controller, occurrence)
  end

  def self.flash_for(outcome)
    case outcome.code
    when :confirmed then [:notice, "You're confirmed for this event."]
    when :waitlisted then [:notice, "You're on the wait list."]
    when :pending, :login_required
      [:notice, "Check your email to finish your RSVP. If you already have an account, log in instead."]
    when :duplicate then [:alert, 'You already have an RSVP for this event.']
    when :host then [:alert, "Hosts can't RSVP to their own event."]
    when :full then [:alert, 'This event is full.']
    when :closed then [:alert, 'RSVPs are closed for this event.']
    else [:alert, 'RSVP could not be saved. Check your name and email.']
    end
  end

  def self.clear(controller)
    controller.session.delete(OCCURRENCE_KEY)
    controller.session.delete(RETURN_KEY)
  end

  def self.event_destination(controller, occurrence)
    return if occurrence.nil?

    controller.event_path(occurrence.event, anchor: 'rsvp')
  end
  private_class_method :clear, :event_destination
end
