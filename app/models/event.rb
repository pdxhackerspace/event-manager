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
  has_one_attached :banner_image do |attachable|
    attachable.variant :thumb, resize_to_limit: [300, 300]
  end

  before_validation :generate_slug, on: :create
  before_validation :update_slug_if_title_changed, on: :update
  before_save :rename_banner_image
  before_create :generate_ical_token
  after_create :add_creator_as_host
  after_create :generate_initial_occurrences
  after_create :log_creation
  after_update :log_update
  after_update :regenerate_occurrences_if_needed
  after_update :cancel_future_occurrences_if_permanently_cancelled
  after_update :reactivate_relocated_occurrences_if_no_longer_relocated
  after_save :log_banner_change
  after_commit :queue_spectra6_processing, if: :banner_image_attached_recently?

  attr_accessor :current_user_for_journal

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

  # Generate future occurrences based on recurrence rules
  def generate_occurrences(limit = nil)
    # Don't generate new occurrences for permanently cancelled or relocated events
    return if permanently_cancelled? || permanently_relocated?

    limit ||= max_occurrences || 5

    # Determine status for new occurrences
    # - cancelled if default_to_cancelled
    # - active otherwise
    occurrence_status = default_to_cancelled? ? 'cancelled' : 'active'

    if recurrence_type == 'once'
      # One-time event - create single occurrence if it doesn't exist
      occ = find_or_create_occurrence_by_date(start_time, occurrence_status)
      occ.save! if occ.changed?
    elsif recurrence_rule.present?
      # Recurring event - generate occurrences
      schedule = IceCube::Schedule.from_yaml(recurrence_rule)
      future_dates = schedule.occurrences_between(Time.current, 1.year.from_now).first(limit)

      future_dates.each do |date|
        occ = find_or_create_occurrence_by_date(date, occurrence_status)
        occ.save! if occ.changed?
      end
    end
  end

  # Find existing occurrence by date (ignoring time) or create new one
  # If existing occurrence has wrong time, update it to the correct time
  def find_or_create_occurrence_by_date(scheduled_time, default_status)
    scheduled_date = scheduled_time.in_time_zone(Time.zone).to_date
    local_time = scheduled_time.in_time_zone(Time.zone)

    # Find occurrence on the same local date
    # We search a window around the date to catch any timezone edge cases,
    # then filter in Ruby for exact date match
    day_start = scheduled_date.beginning_of_day
    day_end = scheduled_date.end_of_day
    candidates = occurrences.where(occurs_at: (day_start - 1.day)..(day_end + 1.day))
    existing = candidates.find { |occ| occ.occurs_at.in_time_zone(Time.zone).to_date == scheduled_date }

    if existing
      # Update time if it's off (DST fix)
      existing_local = existing.occurs_at.in_time_zone(Time.zone)
      existing.occurs_at = scheduled_time if existing_local.hour != local_time.hour || existing_local.min != local_time.min
      existing
    else
      # Create new occurrence
      occurrences.build(occurs_at: scheduled_time, status: default_status)
    end
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
  # This method updates occurrences in place to preserve URLs/slugs
  def regenerate_future_occurrences!
    # Don't modify occurrences for permanently cancelled or relocated events
    return if permanently_cancelled? || permanently_relocated?

    # Get the scheduled future dates
    scheduled_dates = future_scheduled_dates

    # Get existing future occurrences (including non-active ones)
    existing_future = occurrences.where('occurs_at > ?', Time.current)

    # Build a hash of existing occurrences by DATE (not exact time)
    # This handles DST shifts where the time might be off by an hour
    existing_by_date = existing_future.index_by { |occ| occ.occurs_at.in_time_zone(Time.zone).to_date }

    # Build set of scheduled dates for comparison
    scheduled_date_set = scheduled_dates.to_set { |d| d.in_time_zone(Time.zone).to_date }

    # Create or update occurrences for scheduled dates
    occurrence_status = default_to_cancelled? ? 'cancelled' : 'active'
    scheduled_dates.each do |scheduled_time|
      scheduled_date = scheduled_time.in_time_zone(Time.zone).to_date
      existing = existing_by_date[scheduled_date]

      if existing
        # Update time if it's off (DST fix) - preserves slug/status
        update_occurrence_time_if_needed(existing, scheduled_time)
      else
        # Create new occurrence
        occurrences.create!(occurs_at: scheduled_time, status: occurrence_status)
      end
    end

    # Remove occurrences that are no longer scheduled (only active ones)
    # Keep modified occurrences (cancelled, postponed, relocated) as they represent intentional changes
    existing_by_date.each do |date, occ|
      next if scheduled_date_set.include?(date) # Still scheduled
      next unless occ.status == 'active' # Only remove unmodified active occurrences

      occ.destroy
    end
  end

  # Update an occurrence's time if it doesn't match the scheduled time
  def update_occurrence_time_if_needed(occurrence, scheduled_time)
    local_scheduled = scheduled_time.in_time_zone(Time.zone)
    local_existing = occurrence.occurs_at.in_time_zone(Time.zone)

    return if local_existing.hour == local_scheduled.hour && local_existing.min == local_scheduled.min

    # Time is off - update it (preserves slug and status)
    occurrence.update_column(:occurs_at, scheduled_time) # rubocop:disable Rails/SkipsModelValidations
  end

  # Get future scheduled dates based on recurrence rule
  def future_scheduled_dates
    limit = max_occurrences || 5

    if recurrence_type == 'once'
      start_time > Time.current ? [start_time] : []
    elsif recurrence_rule.present?
      schedule = IceCube::Schedule.from_yaml(recurrence_rule)
      schedule.occurrences_between(Time.current, 1.year.from_now).first(limit)
    else
      []
    end
  end

  # Build IceCube schedule from parameters
  def self.build_schedule(start_time, recurrence_type, recurrence_params = {})
    schedule = IceCube::Schedule.new(start_time)

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

  private

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

  def rename_banner_image
    return unless banner_image.attached?
    return unless banner_image.blob.persisted? == false || banner_image.attachment&.new_record?

    blob = banner_image.blob
    extension = File.extname(blob.filename.to_s)
    timestamp = Time.current.to_i
    new_filename = "#{slug || title.parameterize}-banner-#{timestamp}#{extension}"

    blob.filename = new_filename
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
    # Always regenerate occurrences on update to ensure consistency
    # This handles changes to title, description, location, and other fields
    # that should be reflected in all future occurrences
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

      # Store full text for text fields
      if %w[title description more_info_url cancellation_reason].include?(key)
      end
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

  def log_banner_change
    return unless current_user_for_journal
    return if new_record?

    # Check if banner was added
    return unless banner_image.attached? && banner_image.attachment.blob.created_at > 5.seconds.ago

    EventJournal.log_event_change(
      self,
      current_user_for_journal,
      'banner_added',
      {
        'banner_image' => {
          'filename' => banner_image.filename.to_s,
          'size' => "#{(banner_image.byte_size.to_f / 1024).round(2)} KB",
          'content_type' => banner_image.content_type
        }
      }
    )
  end

  def banner_image_attached_recently?
    banner_image.attached? && banner_image.blob.created_at > 10.seconds.ago
  end

  def queue_spectra6_processing
    return unless banner_image.attached?

    Spectra6BannerJob.perform_later(banner_image.blob.id)
  end
end
