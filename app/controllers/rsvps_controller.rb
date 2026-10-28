class RsvpsController < ApplicationController
  GUEST_NOTICE = "Check your email to finish your RSVP. If you already have an account, log in instead.".freeze

  before_action :set_occurrence
  rate_limit to: 5, within: 1.minute, only: :create, by: -> { request.remote_ip }

  def create
    store_location_for(:user, event_path(@occurrence.event, anchor: 'rsvp'))
    unless audience_open?
      return redirect_to(
        new_user_session_path(rsvp_occurrence_id: @occurrence.id, return_to: event_path(@occurrence.event, anchor: 'rsvp')),
        alert: 'Log in to RSVP.'
      )
    end
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
    key, message = RsvpLogin.flash_for(outcome)
    { key => message }
  end
end
