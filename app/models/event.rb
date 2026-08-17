class Event < ApplicationRecord
  include SoftDeletable

  belongs_to :user # Original creator
  belongs_to :location, optional: true
  has_many :event_hosts, dependent: :destroy
  has_many :hosts, through: :event_hosts, source: :user
  has_many :event_occurrences, dependent: :destroy
  has_many :occurrences, class_name: 'EventOccurrence', dependent: :destroy
  has_many :event_journals, dependent: :nullify
  has_many :reminder_postings, dependent: :destroy
  has_many :event_images, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :event
  belongs_to :fixed_event_image, class_name: 'EventImage', optional: true

  before_validation :generate_slug, on: :create
  before_validation :update_slug_if_title_changed, on: :update
  before_create :generate_ical_token
  after_create :add_creator_as_host
  after_create :attach_pool_images
  after_create :generate_initial_occurrences
  after_create :log_creation
  after_update :log_update
  after_update :regenerate_occurrences_if_needed, if: :schedule_affecting_fields_changed?
  after_update :cancel_future_occurrences_if_permanently_cancelled
  after_update :reactivate_relocated_occurrences_if_no_longer_relocated

  attr_accessor :current_user_for_journal, :pool_images

  validates :title, presence: true
  validates :start_time, presence: true
  validates :duration, numericality: { greater_than: 0 }
  validates :recurrence_type, inclusion: { in: %w[once weekly monthly custom] }
  validates :status, inclusion: { in: %w[active postponed cancelled] }
  validates :visibility, inclusion: { in: %w[public members private] }
  validates :open_to, inclusion: { in: %w[public members private] }
  validates :more_info_url,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }, allow_blank: true
  validates :slug, presence: true, uniqueness: true
  validates :relocated_to, presence: { message: "is required when event is permanently relocated" },
                           if: :permanently_relocated?
  validates :image_selection_mode, inclusion: { in: %w[fixed random cycle] }
  validate :fixed_event_image_belongs_to_event

  # Full-text search using pg_trgm (trigram matching)
  # Searches title and description with fuzzy matching
  scope :search, lambda { |query|
    return all if query.blank?

    sanitized_query = "%#{sanitize_sql_like(query)}%"
    where('title ILIKE :q OR description ILIKE :q', q: sanitized_query)
  }

  # Allow finding by slug or ID
  def self.friendly_find(param)
    find_by(slug: param) || find(param)
  end

  def to_param
    slug
  end

  # Placeholder for date/time that will be substituted when used for an occurrence
  WHEN_PLACEHOLDER = '{{when}}'.freeze

  # Default short reminder message (for Bluesky - limited characters)
  # Uses {{when}} placeholder for date/time
  def reminder_short_default(_days_ahead = nil)
    "#{title} is coming up #{WHEN_PLACEHOLDER} at PDX Hackerspace. Join us!"
  end

  # Default long reminder message (for Slack/Instagram - more detail allowed)
  # Uses {{when}} placeholder for date/time
  def reminder_long_default(_days_ahead = nil)
    msg = "#{title} is happening #{WHEN_PLACEHOLDER} at PDX Hackerspace!"
    msg += " #{description.truncate(400)}" if description.present?
    msg
  end

  scope :active, -> { where(status: 'active') }
  scope :postponed, -> { where(status: 'postponed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :permanently_cancelled, -> { where(permanently_cancelled: true) }
  scope :not_permanently_cancelled, -> { where(permanently_cancelled: false) }
  scope :default_to_cancelled, -> { where(default_to_cancelled: true) }
  scope :permanently_relocated, -> { where(permanently_relocated: true) }
  scope :not_permanently_relocated, -> { where(permanently_relocated: false) }
  scope :public_events, -> { where(visibility: 'public') }
  scope :members_events, -> { where(visibility: 'members') }
  scope :private_events, -> { where(visibility: 'private') }
  scope :published, -> { where(draft: false) }
  scope :drafts, -> { where(draft: true) }

  # Get occurrence dates for a date range (from IceCube schedule)
  def occurrence_dates(start_date, end_date)
    return [] if recurrence_rule.blank?

    schedule = IceCube::Schedule.from_yaml(recurrence_rule)
    schedule.occurrences_between(start_date, end_date)
  end

  # Check if event is recurring
  def recurring?
    recurrence_type != 'once'
  end

  # Visibility helpers
  def public?
    visibility == 'public'
  end

  def members_only?
    visibility == 'members'
  end

  def private?
    visibility == 'private'
  end

  # Mark event as postponed
  def postpone!(until_date, reason = nil)
    update(status: 'postponed', postponed_until: until_date, cancellation_reason: reason)
  end

  # Mark event as cancelled
  def cancel!(reason = nil)
    update(status: 'cancelled', cancellation_reason: reason)
  end

  # Reactivate event
  def reactivate!
    update(status: 'active', postponed_until: nil, cancellation_reason: nil)
  end

  # Host management
  def hosted_by?(user)
    return false unless user

    # Use a direct query to avoid association caching issues
    user.admin? || EventHost.exists?(event_id: id, user_id: user.id)
  end

  # rubocop:disable Naming/PredicateMethod
  def add_host(user)
    # Check if user is already in the hosts list (not just if they have host permissions)
    return false if host_ids.include?(user.id)

    hosts << user
    true
  end
  # rubocop:enable Naming/PredicateMethod

  def remove_host(user)
    # Don't allow removing the only host (event must have at least one host)
    return false if hosts.count <= 1

    event_hosts.find_by(user: user)&.destroy
  end

  def creator
    user
  end

  def banner_image
    (fallback_event_image || EventImage.new).image
  end

  def fallback_event_image
    fixed_event_image || event_images.pooled.first
  end

  def pooled_images
    event_images.pooled.ordered
  end

  # Generate future occurrences based on recurrence rules
  # Delegates to OccurrenceGenerator service
  def generate_occurrences(limit = nil)
    OccurrenceGenerator.new(self).generate(limit: limit)
  end

  # Find existing occurrence by date (ignoring time) or create new one
  # Delegates to OccurrenceGenerator service
  def find_or_create_occurrence_by_date(scheduled_time, default_status)
    OccurrenceGenerator.new(self).find_or_create_occurrence_by_date(scheduled_time, default_status)
  end

  # Get upcoming active occurrences
  def upcoming_occurrences(limit = nil)
    limit ||= max_occurrences || 5
    occurrences.upcoming.active.limit(limit)
  end

  # Check for conflicts with other events
  def check_conflicts(limit = 5)
    return [] if persisted? && occurrences.empty?

    # Get the first few occurrences to check
    times_to_check = if persisted?
                       occurrences.limit(limit).pluck(:occurs_at)
                     elsif recurrence_type == 'once'
                       [start_time]
                     elsif recurrence_rule.present?
                       schedule = IceCube::Schedule.from_yaml(recurrence_rule)
                       schedule.occurrences_between(start_time, 1.year.from_now).first(limit)
                     else
                       [start_time]
                     end

    return [] if times_to_check.empty?

    # Find overlapping occurrences from other events
    conflicting_occurrences = EventOccurrence
                              .joins(:event)
                              .where(events: { status: 'active' })

    conflicting_occurrences = conflicting_occurrences.where.not(event_id: id) if persisted?

    conflicts = []
    times_to_check.each do |occurrence_time|
      # Check for events that overlap (within 15 minutes before or after)
      range_start = occurrence_time - 15.minutes
      range_end = occurrence_time + duration.minutes + 15.minutes

      overlapping = conflicting_occurrences
                    .where('event_occurrences.occurs_at >= ? AND event_occurrences.occurs_at <= ?', range_start, range_end)
                    .includes(event: :location)
                    .limit(3) # Limit to 3 conflicts per time slot

      overlapping.each do |occ|
        conflicts << {
          event: occ.event,
          occurrence: occ,
          overlap_time: occurrence_time
        }
      end
    end

    conflicts.uniq { |c| c[:event].id }.first(5) # Return up to 5 unique conflicting events
  end

  # Regenerate occurrences (useful after recurrence rule changes)
  # Delegates to OccurrenceGenerator service
  def regenerate_future_occurrences!
    OccurrenceGenerator.new(self).regenerate_future!
  end

  # Update an occurrence's time if it doesn't match the scheduled time
  # Delegates to OccurrenceGenerator service
  def update_occurrence_time_if_needed(occurrence, scheduled_time)
    OccurrenceGenerator.new(self).update_occurrence_time_if_needed(occurrence, scheduled_time)
  end

  # Get future scheduled dates based on recurrence rule
  # Delegates to OccurrenceGenerator service
  def future_scheduled_dates
    OccurrenceGenerator.new(self).future_scheduled_dates
  end

  # Build IceCube schedule from parameters
  def self.build_schedule(start_time, recurrence_type, recurrence_params = {})
    return nil if start_time.nil?

    local_start = start_time.in_time_zone(Time.zone)
    schedule = IceCube::Schedule.new(local_start)

    case recurrence_type
    when 'weekly'
      # Weekly on specific day(s) with optional interval
      days = recurrence_params[:days] || [start_time.wday]
      interval = (recurrence_params[:interval] || 1).to_i
      interval = 1 if interval < 1

      # Convert day numbers to IceCube day symbols
      day_map = { 0 => :sunday, 1 => :monday, 2 => :tuesday, 3 => :wednesday,
                  4 => :thursday, 5 => :friday, 6 => :saturday }
      day_symbols = days.map { |d| day_map[d.to_i] }.compact

      rule = IceCube::Rule.weekly(interval).day(*day_symbols)
      schedule.add_recurrence_rule(rule)

    when 'monthly'
      build_monthly_schedule(schedule, start_time, recurrence_params)

    when 'custom'
      # Custom allows combining multiple rules
      build_custom_schedule(schedule, start_time, recurrence_params)
    end

    schedule
  end

  def self.build_monthly_schedule(schedule, start_time, recurrence_params)
    occurrence_map = { 'first' => 1, 'second' => 2, 'third' => 3, 'fourth' => 4, 'last' => -1 }

    if recurrence_params[:occurrences].present? && recurrence_params[:day]
      # e.g., "first and third Tuesday", "second Monday"
      occurrence_ints = recurrence_params[:occurrences].map { |occ| occurrence_map[occ.to_s] }.compact
      day = recurrence_params[:day].to_sym
      rule = IceCube::Rule.monthly.day_of_week(day => occurrence_ints)
      schedule.add_recurrence_rule(rule)

      # Handle exceptions (e.g., "every Saturday except the last")
      add_monthly_exceptions(schedule, recurrence_params)

    elsif recurrence_params[:occurrence] && recurrence_params[:day]
      # Backward compatibility with single occurrence
      occurrence_int = occurrence_map[recurrence_params[:occurrence].to_s]
      day = recurrence_params[:day].to_sym
      rule = IceCube::Rule.monthly.day_of_week(day => [occurrence_int])
      schedule.add_recurrence_rule(rule)
    else
      # Monthly on the same day of month
      rule = IceCube::Rule.monthly.day_of_month(start_time.day)
      schedule.add_recurrence_rule(rule)
    end
  end

  def self.add_monthly_exceptions(schedule, recurrence_params)
    return unless recurrence_params[:except_occurrences].present? && recurrence_params[:day]

    occurrence_map = { 'first' => 1, 'second' => 2, 'third' => 3, 'fourth' => 4, 'last' => -1 }
    except_ints = recurrence_params[:except_occurrences].map { |occ| occurrence_map[occ.to_s] }.compact
    return if except_ints.empty?

    day = recurrence_params[:day].to_sym
    except_rule = IceCube::Rule.monthly.day_of_week(day => except_ints)
    schedule.add_exception_rule(except_rule)
  end

  def self.build_custom_schedule(schedule, start_time, recurrence_params)
    # Custom schedule can have multiple weekly rules for complex patterns
    # e.g., "Every other Tuesday AND every other Thursday on alternating weeks"
    return if recurrence_params[:custom_rules].blank?

    recurrence_params[:custom_rules].each do |rule_params|
      case rule_params[:type]
      when 'weekly'
        interval = (rule_params[:interval] || 1).to_i
        days = rule_params[:days] || [start_time.wday]
        week_offset = (rule_params[:week_offset] || 0).to_i
        day_map = { 0 => :sunday, 1 => :monday, 2 => :tuesday, 3 => :wednesday,
                    4 => :thursday, 5 => :friday, 6 => :saturday }
        day_symbols = days.map { |d| day_map[d.to_i] }.compact

        # If there's a week offset, we need to add explicit recurrence times
        # to shift this rule's occurrences by the offset number of weeks
        if week_offset.positive? && interval > 1
          # Add recurrence times for the offset pattern
          # Calculate the first occurrence for each day, offset by week_offset weeks
          add_offset_weekly_occurrences(schedule, start_time, interval, day_symbols, week_offset)
        else
          rule = IceCube::Rule.weekly(interval).day(*day_symbols)
          schedule.add_recurrence_rule(rule)
        end
      when 'monthly'
        build_monthly_schedule(schedule, start_time, rule_params)
      end
    end
  end

  # Add weekly occurrences with a week offset for alternating patterns
  def self.add_offset_weekly_occurrences(schedule, start_time, interval, day_symbols, week_offset)
    day_map_reverse = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3,
                        thursday: 4, friday: 5, saturday: 6 }

    day_symbols.each do |day_sym|
      target_wday = day_map_reverse[day_sym]

      # Find the first occurrence of this day of week on or after start_time
      first_occurrence = start_time
      days_until_target = (target_wday - first_occurrence.wday) % 7
      first_occurrence += days_until_target.days

      # Apply the week offset
      first_occurrence += week_offset.weeks

      # Add occurrences for 2 years (enough for typical event planning)
      current = first_occurrence
      end_date = start_time + 2.years
      while current <= end_date
        schedule.add_recurrence_time(current)
        current += interval.weeks
      end
    end
  end

  # Check if any fields that affect occurrence scheduling have changed
  def schedule_affecting_fields_changed?
    saved_change_to_start_time? ||
      saved_change_to_recurrence_type? ||
      saved_change_to_recurrence_rule? ||
      saved_change_to_max_occurrences? ||
      saved_change_to_permanently_cancelled? ||
      saved_change_to_permanently_relocated? ||
      saved_change_to_default_to_cancelled?
  end

  def attach_pool_images_from_uploads(files)
    Array(files).compact_blank.each_with_index do |file, index|
      event_images.create!(position: index, in_pool: true).tap do |event_image|
        event_image.image.attach(file)
      end
    end

    return if fixed_event_image_id.present?

    first_image = event_images.pooled.ordered.first
    update_column(:fixed_event_image_id, first_image.id) if first_image # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def attach_pool_images
    return if pool_images.blank?

    attach_pool_images_from_uploads(pool_images)
  end

  def fixed_event_image_belongs_to_event
    return if fixed_event_image_id.blank?
    return if event_images.exists?(id: fixed_event_image_id)

    errors.add(:fixed_event_image_id, 'must belong to this event')
  end

  def generate_slug
    return if slug.present?
    return if title.blank?

    base_slug = title.parameterize
    new_slug = base_slug
    counter = 1

    # Check against ALL events including soft-deleted ones to avoid conflicts
    while Event.unscoped.exists?(slug: new_slug)
      new_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = new_slug
  end

  def update_slug_if_title_changed
    return unless title_changed?

    generate_slug
  end

  def generate_ical_token
    self.ical_token = SecureRandom.urlsafe_base64(32)
  end

  def add_creator_as_host
    # Automatically add the creator as the first host
    return if user.nil?

    # Check if already a host using a direct query to avoid caching issues
    return if EventHost.exists?(event_id: id, user_id: user.id)

    EventHost.create!(event: self, user: user)
    # Reload the hosts association to ensure it's up to date
    hosts.reload
  end

  def generate_initial_occurrences
    # Generate occurrences when event is first created
    generate_occurrences
  end

  def regenerate_occurrences_if_needed
    # Regenerate occurrences when schedule-affecting fields change
    # Only triggered by: start_time, recurrence_type, recurrence_rule,
    # max_occurrences, permanently_cancelled, permanently_relocated, default_to_cancelled
    regenerate_future_occurrences!
  rescue StandardError => e
    Rails.logger.error "Failed to regenerate occurrences for event #{id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise # Re-raise to rollback the transaction
  end

  def cancel_future_occurrences_if_permanently_cancelled
    return unless saved_change_to_permanently_cancelled? && permanently_cancelled?

    # Cancel all future active occurrences when event becomes permanently cancelled
    occurrences.where('occurs_at > ?', Time.current).where(status: 'active').find_each do |occ|
      occ.update!(status: 'cancelled', cancellation_reason: 'Event permanently cancelled')
    end
  end

  def reactivate_relocated_occurrences_if_no_longer_relocated
    return unless saved_change_to_permanently_relocated?
    return if permanently_relocated? # Only run when turning OFF permanently_relocated

    # Reactivate future relocated occurrences when event is no longer permanently relocated
    occurrences.where('occurs_at > ?', Time.current).where(status: 'relocated').find_each do |occ|
      occ.update!(status: 'active', relocated_to: nil, cancellation_reason: nil)
    end
  end

  def log_creation
    return unless current_user_for_journal

    EventJournal.log_event_change(
      self,
      current_user_for_journal,
      'created',
      {
        'title' => title,
        'recurrence_type' => recurrence_type,
        'visibility' => visibility,
        'open_to' => open_to
      }
    )
  end

  def log_update
    return unless current_user_for_journal
    return unless saved_changes.any?

    tracked_changes = {}
    saved_changes.each do |key, (old_val, new_val)|
      # Skip timestamps and internal fields
      next if %w[updated_at created_at ical_token].include?(key)

      tracked_changes[key] = { 'from' => old_val, 'to' => new_val }
    end

    return if tracked_changes.empty?

    EventJournal.log_event_change(
      self,
      current_user_for_journal,
      'updated',
      tracked_changes
    )
  end
end
