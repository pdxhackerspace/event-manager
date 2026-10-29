class ExclusiveRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_event, only: %i[show approve deny]
  before_action :authorize_review

  def index
    pending = Event.where(exclusive_status: 'pending').includes(:exclusive_requested_by, :user)
                   .order(exclusive_requested_at: :asc)
    @pagy, @pending = pagy(:offset, pending)
    @decided = Event.where(exclusive_status: %w[approved denied])
                    .includes(:exclusive_reviewed_by)
                    .order(exclusive_reviewed_at: :desc)
                    .limit(20)
  end

  def show
    @result = ScheduleConflictChecker.for_event(@event)
    @covered = @result.covered.group_by(&:candidate_starts_at)
  end

  def approve
    ExclusiveRequest.new(@event, actor: current_user).approve!(note: params[:note])
    redirect_to exclusive_requests_path, notice: "Approved exclusive scheduling for #{@event.title}."
  end

  def deny
    ExclusiveRequest.new(@event, actor: current_user).deny!(note: params[:note])
    redirect_to exclusive_requests_path, notice: "Denied exclusive scheduling for #{@event.title}."
  end

  private

  def set_event
    @event = Event.friendly_find(params[:id])
  end

  def authorize_review
    authorize @event || Event, :review_exclusive?
  end
end
