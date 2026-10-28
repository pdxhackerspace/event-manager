class RsvpManagementController < ApplicationController
  before_action :set_rsvp
  before_action :reject_if_over, except: :show

  def show; end

  def confirm
    redirect_with RsvpService.new(@occurrence).confirm_pending!(@rsvp)
  end

  def cancel
    redirect_with RsvpService.new(@occurrence).cancel!(@rsvp, via: 'self')
  end

  def claim
    redirect_with RsvpService.new(@occurrence).claim!(@rsvp)
  end

  def decline
    redirect_with RsvpService.new(@occurrence).decline!(@rsvp)
  end

  def update_reminders
    @rsvp.update!(reminders_opted_out: params[:reminders_opted_out] == '1')
    redirect_to manage_rsvp_path(@rsvp.manage_token), notice: 'Reminder preference saved.'
  end

  private

  def set_rsvp
    @rsvp = Rsvp.find_by!(manage_token: params.expect(:token))
    @occurrence = @rsvp.event_occurrence
    @event = @occurrence.event
  end

  def reject_if_over
    return if @occurrence.manageable_until?

    redirect_to manage_rsvp_path(@rsvp.manage_token), alert: 'This event is over.'
  end

  def redirect_with(outcome)
    redirect_to manage_rsvp_path(@rsvp.manage_token), **flash_for(outcome)
  end

  def flash_for(outcome)
    case outcome.code
    when :confirmed then { notice: "You're confirmed." }
    when :waitlisted then { notice: "You're on the wait list." }
    when :cancelled then { notice: 'Your RSVP is cancelled. Your spot has been released.' }
    when :taken then { alert: 'That spot was just taken. You are still on the wait list.' }
    when :held then { alert: 'That spot is being held for someone else. You are still on the wait list.' }
    when :full then { alert: 'This event is full.' }
    when :closed then { alert: 'RSVPs are closed for this event.' }
    else { alert: 'That RSVP can no longer be changed.' }
    end
  end
end
