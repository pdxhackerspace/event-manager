# frozen_string_literal: true

class ReminderPostingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_posting, only: %i[destroy]
  before_action :authorize_posting, only: %i[destroy]
  before_action :authorize_admin, only: %i[index]

  # GET /reminder_postings - Admin only, shows all postings
  def index
    @postings = ReminderPosting.includes(:event, :event_occurrence, :deleted_by)
                               .recent_first
                               .limit(200)
  end

  # DELETE /reminder_postings/:id - Delete/retract a posting
  def destroy
    if @posting.deleted?
      redirect_back_or_to event_path(@posting.event), alert: 'This posting has already been deleted.'
      return
    end

    # Try to delete from the platform if possible
    deleted_from_platform = attempt_platform_delete

    # Mark as deleted locally
    @posting.mark_deleted!(current_user)

    notice = if deleted_from_platform
               "Post deleted from #{@posting.platform_display_name} and marked as removed."
             else
               "Post marked as removed (could not delete from #{@posting.platform_display_name})."
             end

    redirect_back_or_to event_path(@posting.event), notice: notice
  end

  private

  def set_posting
    @posting = ReminderPosting.find(params.expect(:id))
  end

  def authorize_posting
    @event = @posting.event
    return if current_user.admin? || @event.hosted_by?(current_user)

    redirect_to root_path, alert: 'You are not authorized to manage this posting.'
  end

  def authorize_admin
    return if current_user&.admin?

    redirect_to root_path, alert: 'You must be an admin to view all postings.'
  end

  def attempt_platform_delete
    case @posting.platform
    when 'bluesky'
      return false if @posting.post_uid.blank?

      result = SocialService.delete_bluesky_post(@posting.post_uid)
      result[:success]
    else
      # Slack webhooks and Instagram don't support delete via API
      false
    end
  end
end
