class EventImagePolicy < ApplicationPolicy
  def create?
    manage_event?
  end

  def update?
    manage_event?
  end

  def destroy?
    manage_event?
  end

  def reorder?
    manage_event?
  end

  private

  def manage_event?
    return false unless user

    EventPolicy.new(user, record.event).update?
  end
end
