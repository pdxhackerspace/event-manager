class ExclusiveRequestMailer < ApplicationMailer
  def self.deliver_review_needed(event)
    recipients = User.where(role: 'admin').pluck(:email)
    return if recipients.empty?

    review_needed(event, recipients).deliver_later
  end

  def self.deliver_decision(event)
    recipients = event.hosts.pluck(:email)
    return if recipients.empty?

    decision(event, recipients).deliver_later
  end

  def review_needed(event, recipients)
    @event = event
    @requester = event.exclusive_requested_by
    @site_config = SiteConfig.current
    @covered = ScheduleConflictChecker.for_event(event).covered
    @test_mode = EmailTestMode.test_mode?
    mail(to: deliverable(recipients), subject: review_subject)
  end

  def decision(event, recipients)
    @event = event
    @site_config = SiteConfig.current
    @test_mode = EmailTestMode.test_mode?
    mail(to: deliverable(recipients), subject: decision_subject)
  end

  private

  def deliverable(recipients)
    recipients.map { |address| EmailTestMode.recipient_for(address) }.uniq
  end

  def review_subject
    "[#{organization_name}] Exclusive scheduling needs review: #{@event.title}"
  end

  def decision_subject
    verdict = @event.exclusive_approved? ? 'approved' : 'denied'
    "[#{organization_name}] Exclusive scheduling #{verdict}: #{@event.title}"
  end

  def organization_name
    @site_config&.organization_name || 'EventManager'
  end
end
