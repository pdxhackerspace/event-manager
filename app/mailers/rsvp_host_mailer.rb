class RsvpHostMailer < ApplicationMailer
  def rsvp_activity(user, rsvp, action)
    @user = user
    @rsvp = rsvp
    @action = action
    @occurrence = rsvp.event_occurrence
    @event = @occurrence.event
    @site_config = SiteConfig.current
    @test_mode = EmailTestMode.test_mode?
    @counts = {
      confirmed: @occurrence.rsvps.confirmed.count,
      waitlisted: @occurrence.rsvps.waitlisted.count
    }
    mail(to: EmailTestMode.recipient_for(user.email), subject: subject)
  end

  private

  def subject
    "[#{@site_config&.organization_name || 'EventManager'}] RSVP update for #{@event.title}"
  end
end
