class RsvpsController < ApplicationController
  GUEST_NOTICE = "Check your email to finish your RSVP. If you already have an account, log in instead.".freeze

  before_action :set_occurrence
  rate_limit to: 5, within: 1.minute, only: :create, by: -> { request.remote_ip }

  def create
    store_location_for(:user, event_occurrence_path(@occurrence))
    return redirect_to(new_user_session_path, alert: 'Log in to RSVP.') unless audience_open?
    return redirect_to(@occurrence, notice: GUEST_NOTICE) if params[:company_website].present?

    outcome = RsvpService.new(@occurrence).create(user: current_user, name: params[:name], email: params[:email])
    redirect_to @occurrence, **flash_for(outcome)
  end

  private

  def set_occurrence
    @occurrence = EventOccurrence.friendly_find(params[:event_occurrence_id])
  end

  def audience_open?
    return true if @occurrence.event.open_to == 'public'

    current_user.present?
  end

  def flash_for(outcome)
    case outcome.code
    when :confirmed then { notice: "You're confirmed for this event." }
    when :waitlisted then { notice: "You're on the wait list." }
    when :pending, :login_required then { notice: GUEST_NOTICE }
    when :duplicate then { alert: 'You already have an RSVP for this event.' }
    when :full then { alert: 'This event is full.' }
    when :closed then { alert: 'RSVPs are closed for this event.' }
    else { alert: 'RSVP could not be saved. Check your name and email.' }
    end
  end
end
