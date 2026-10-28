class OccurrenceRsvpsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_occurrence
  before_action :authorize_host

  def index
    @status = params[:status].presence || 'confirmed'
    @status = 'confirmed' unless Rsvp::STATUSES.include?(@status)
    @rsvps = @occurrence.rsvps.where(status: @status).includes(:user).order(:waitlisted_at, :confirmed_at, :created_at)
  end

  def export
    send_data csv, filename: "rsvps-#{@occurrence.slug}.csv", type: 'text/csv'
  end

  def add
    outcome = RsvpService.new(@occurrence).create(name: params[:name], email: params[:email], manual: true)
    journal_add(outcome)
    redirect_to event_occurrence_rsvps_path(@occurrence), **flash_for(outcome)
  end

  def cancel
    outcome = RsvpService.new(@occurrence).cancel!(rsvp, actor: current_user, via: actor_via, reason: params[:reason])
    redirect_to event_occurrence_rsvps_path(@occurrence, status: rsvp.status == 'cancelled' ? 'cancelled' : params[:status]),
                **flash_for(outcome)
  end

  def promote
    outcome = RsvpService.new(@occurrence).promote!(rsvp, actor: current_user)
    redirect_to event_occurrence_rsvps_path(@occurrence), **flash_for(outcome)
  end

  def resend
    RsvpNotifier.resend(rsvp)
    redirect_to event_occurrence_rsvps_path(@occurrence, status: rsvp.status), notice: 'Email queued.'
  end

  def check_in
    outcome = RsvpService.new(@occurrence).check_in!(rsvp, actor: current_user, attended: params[:attended] == '1')
    redirect_to event_occurrence_rsvps_path(@occurrence), **flash_for(outcome)
  end

  private

  def set_occurrence
    @occurrence = EventOccurrence.friendly_find(params[:event_occurrence_id])
    @event = @occurrence.event
  end

  def authorize_host
    return if current_user.admin? || @event.hosted_by?(current_user)

    redirect_to @occurrence, alert: 'You are not authorized to manage RSVPs.'
  end

  def rsvp
    @rsvp ||= @occurrence.rsvps.find(params.expect(:id))
  end

  def actor_via
    current_user.admin? ? 'admin' : 'host'
  end

  def journal_add(outcome)
    return unless outcome.ok?

    EventJournal.log_occurrence_change(@occurrence, current_user, 'rsvp_added', { 'name' => outcome.rsvp.display_name })
  end

  def flash_for(outcome)
    case outcome.code
    when :confirmed then { notice: "#{outcome.rsvp.display_name} is confirmed." }
    when :waitlisted then { notice: "#{outcome.rsvp.display_name} is on the wait list." }
    when :cancelled then { notice: 'RSVP cancelled.' }
    when :checked_in then { notice: 'Check-in saved.' }
    when :full then { alert: 'There is no open spot.' }
    when :duplicate then { alert: 'That person already has an RSVP.' }
    when :host then { alert: "Hosts can't RSVP to their own event." }
    else { alert: 'RSVP could not be saved.' }
    end
  end

  def csv
    headers = %w[Name Status Attendance]
    headers += ['Full name', 'Email'] if current_user.admin?
    lines = [headers]
    @occurrence.rsvps.includes(:user).order(:status, :id).each do |row|
      line = [row.display_name, row.status, attendance(row)]
      line += [row.user&.name || row.name, row.email] if current_user.admin?
      lines << line
    end
    lines.map { |line| line.map { |value| csv_cell(value) }.join(',') }.join("\n")
  end

  def csv_cell(value)
    text = value.to_s
    return text unless text.match?(/[",\n]/)

    "\"#{text.gsub('"', '""')}\""
  end

  def attendance(row)
    return '' if row.attended.nil?

    row.attended? ? 'attended' : 'no-show'
  end
end
