# Finds events whose times overlap a candidate schedule.
#
# Exclusive (approved) events block. Busy events, and exclusive requests that
# are still pending, only caution. A separate nearby list keeps the older
# 15-minute warning.
class ScheduleConflictChecker
  NEARBY_MINUTES = 15
  HORIZON = 1.year
  KIND_PRIORITY = { exclusive: 5, pending_exclusive: 4, reserved_overlap: 3, busy: 2, nearby: 1 }.freeze

  Conflict = Data.define(:event, :occurrence, :kind, :buffer_minutes, :candidate_starts_at)
  Result = Data.define(:conflicts, :covered) do
    def blocks = conflicts.select { |conflict| conflict.kind == :exclusive }
    def cautions = conflicts.select { |conflict| conflict.kind != :exclusive && conflict.kind != :nearby }
    def nearby = conflicts.select { |conflict| conflict.kind == :nearby }
  end

  def self.for_event(event)
    new(
      windows: windows_for(event),
      exclude_event_id: event.id,
      busy: event.busy?,
      reserves: event.exclusive_pending? || event.exclusive_approved?,
      buffer_minutes: event.effective_conflict_buffer_minutes
    ).call
  end

  def self.for_occurrence(occurrence)
    start = occurrence.occurs_at
    return empty_result if start.blank?

    new(
      windows: [{ starts_at: start, ends_at: start + occurrence.duration.to_i.minutes }],
      exclude_event_id: occurrence.event_id,
      busy: occurrence.event.busy?,
      reserves: occurrence.event.exclusive_pending? || occurrence.event.exclusive_approved?,
      buffer_minutes: occurrence.event.effective_conflict_buffer_minutes
    ).call
  end

  def self.windows_for(event)
    return [] if event.start_time.blank?

    duration = event.duration.to_i.minutes
    occurrence_times(event).filter_map do |time|
      finish = time + duration
      next if finish <= Time.current

      { starts_at: time, ends_at: finish }
    end
  end

  def self.occurrence_times(event)
    return [event.start_time] if event.recurrence_type == 'once' || event.recurrence_rule.blank?

    schedule = IceCube::Schedule.from_yaml(event.recurrence_rule)
    times = schedule.occurrences_between(event.start_time, HORIZON.from_now)
    times.presence || [event.start_time]
  rescue StandardError
    [event.start_time]
  end

  def self.empty_result
    Result.new([], [])
  end

  def initialize(windows:, exclude_event_id:, busy:, reserves:, buffer_minutes:)
    @windows = windows
    @exclude_event_id = exclude_event_id
    @busy = busy
    @reserves = reserves
    @buffer_minutes = buffer_minutes
  end

  def call
    return self.class.empty_result if @windows.empty?

    best = {}
    covered = []
    candidates.each do |occurrence|
      consider(occurrence, best, covered)
    end

    Result.new(best.values, covered.uniq { |conflict| conflict.occurrence.id })
  end

  private

  def candidates
    earliest = @windows.min_by { |window| window[:starts_at] }[:starts_at]
    latest = @windows.max_by { |window| window[:ends_at] }[:ends_at]
    pad = [max_known_buffer, @buffer_minutes.to_i].max.minutes + 1.day

    scope = EventOccurrence.active.joins(:event).merge(Event.active.published)
                           .where(occurs_at: (earliest - pad)..(latest + pad))
                           .includes(:event)
    scope = scope.where.not(event_id: @exclude_event_id) if @exclude_event_id
    scope
  end

  def max_known_buffer
    custom = Event.where.not(conflict_buffer_minutes: nil).maximum(:conflict_buffer_minutes).to_i
    [custom, SiteConfig.current.default_conflict_buffer_minutes.to_i].max
  end

  def consider(occurrence, best, covered)
    @windows.each do |window|
      kind, buffer = classify(window, occurrence)
      record_covered(covered, occurrence, window) if covers?(window, occurrence)
      next unless kind

      current = best[occurrence.event_id]
      next if current && KIND_PRIORITY[current.kind] >= KIND_PRIORITY[kind]

      best[occurrence.event_id] = Conflict.new(
        event: occurrence.event,
        occurrence: occurrence,
        kind: kind,
        buffer_minutes: buffer,
        candidate_starts_at: window[:starts_at]
      )
    end
  end

  def record_covered(covered, occurrence, window)
    covered << Conflict.new(
      event: occurrence.event,
      occurrence: occurrence,
      kind: :covered,
      buffer_minutes: @buffer_minutes,
      candidate_starts_at: window[:starts_at]
    )
  end

  def covers?(window, occurrence)
    return false unless @reserves

    other_start = occurrence.occurs_at
    other_end = other_start + occurrence.duration.to_i.minutes
    buffer = @buffer_minutes.to_i.minutes
    overlaps?(window[:starts_at] - buffer, window[:ends_at] + buffer, other_start, other_end)
  end

  def classify(window, occurrence)
    other_start = occurrence.occurs_at
    other_end = other_start + occurrence.duration.to_i.minutes
    other_buffer = buffer_for(occurrence.event).minutes
    candidate_buffer = @buffer_minutes.to_i.minutes
    protected_other = [other_start - other_buffer, other_end + other_buffer]
    protected_candidate = [window[:starts_at] - candidate_buffer, window[:ends_at] + candidate_buffer]

    hits_other = overlaps?(window[:starts_at], window[:ends_at], *protected_other)
    return [:exclusive, buffer_for(occurrence.event)] if occurrence.event.exclusive_approved? && hits_other
    return [:pending_exclusive, buffer_for(occurrence.event)] if occurrence.event.exclusive_pending? && hits_other

    covers_other = overlaps?(*protected_candidate, other_start, other_end)
    return [:reserved_overlap, @buffer_minutes.to_i] if @reserves && covers_other

    from_other = occurrence.event.busy? && hits_other
    from_self = @busy && covers_other
    return [:busy, from_other ? buffer_for(occurrence.event) : @buffer_minutes.to_i] if from_other || from_self

    return unless nearby?(window, other_start)

    [:nearby, 0]
  end

  def nearby?(window, other_start)
    other_start.between?(window[:starts_at] - NEARBY_MINUTES.minutes, window[:ends_at] + NEARBY_MINUTES.minutes)
  end

  def buffer_for(event)
    event.conflict_buffer_minutes || SiteConfig.current.default_conflict_buffer_minutes
  end

  def overlaps?(start_a, end_a, start_b, end_b)
    start_a < end_b && start_b < end_a
  end
end
