class EventHostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_event
  before_action :authorize_event_management

  def create
    @user_to_add = User.find(params.expect(:user_id))

    if @event.add_host(@user_to_add)
      # Log the host addition
      EventJournal.log_event_change(
        @event,
        current_user,
        'host_added',
        { 'added_host' => @user_to_add.name || @user_to_add.email }
      )
      redirect_to @event, notice: "#{@user_to_add.name || @user_to_add.email} was added as a host."
    else
      redirect_to @event, alert: "#{@user_to_add.name || @user_to_add.email} is already a host of this event."
    end
  end

  def destroy
    @host = User.find(params.expect(:id))
    host_name = @host.name || @host.email

    if @event.remove_host(@host)
      # Log the host removal
      EventJournal.log_event_change(
        @event,
        current_user,
        'host_removed',
        { 'removed_host' => host_name }
      )
      redirect_to @event, notice: "Host was removed."
    else
      redirect_to @event, alert: "Could not remove host. The creator must remain as a host if they're the only one."
    end
  end

  private

  def set_event
    @event = Event.friendly_find(params[:event_id])
  end

  def authorize_event_management
    return if current_user.admin? || @event.hosted_by?(current_user)

    redirect_to @event, alert: "You are not authorized to manage hosts for this event."
  end
end
