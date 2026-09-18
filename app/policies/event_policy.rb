class EventPolicy < ApplicationPolicy
  def index?
    true # Anyone can view events list
  end

  def show?
    # Hosts and admins can always see what they manage, drafts and private
    # events included, so viewing never falls behind editing.
    return true if host?

    # Unpublished events stay hidden from everyone else.
    return false if record.draft?

    return true if record.public?
    return true if record.members_only? && user.present?

    false
  end

  def create?
    user.present? && (user.admin? || user.can_create_events?)
  end

  def update?
    host?
  end

  def destroy?
    user.present? && (user.admin? || user == record.user)
  end

  def postpone?
    update?
  end

  def cancel?
    update?
  end

  def reactivate?
    update?
  end

  class Scope < Scope
    def resolve
      # Not signed in - only published public events
      return scope.published.public_events if user.blank?

      # Admins see everything, including drafts
      return scope.all if user.admin?

      # Published events open to signed-in users, plus every event the user
      # hosts, which covers their own drafts and private events.
      scope.published.where(visibility: %w[public members])
           .or(scope.where(id: EventHost.where(user: user).select(:event_id)))
    end
  end

  private

  # hosted_by? already treats admins as hosts of every event.
  def host?
    user.present? && record.hosted_by?(user)
  end
end
