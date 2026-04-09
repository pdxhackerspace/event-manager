class EventOccurrence < ApplicationRecord # rubocop:disable Metrics/ClassLength
  include SoftDeletable

  belongs_to :event, counter_cache: true
  belongs_to :location, optional: true
  has_many :reminder_postings, dependent: :destroy
  has_one_attached :banner_image do |attachable|
    attachable.variant :thumb, resize_to_limit: [300, 300]
  end

  # Slugs are stable identifiers; only generate on create.
  before_validation :generate_slug, on: :create
  before_save :rename_banner_image

  validates :occurs_at, presence: true
  validates :status, inclusion: { in: %w[active postponed cancelled relocated] }
  validates :slug, presence: true, uniqueness: true
  validates :relocated_to, presence: true, if: -> { status == 'relocated' }

  # Allow finding by slug or ID
  def self.friendly_find(param)
    find_by(slug: param) || find(param)
  end

  def to_param
    slug
  end

  scope :active, -> { where(status: 'active') }
  scope :postponed, -> { where(status: 'postponed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :relocated, -> { where(status: 'relocated') }
  scope :upcoming, -> { where('occurs_at >= ?', Time.current).order(:occurs_at) }
  scope :past, -> { where('occurs_at < ?', Time.current).order(occurs_at: :desc) }

  # Format the date/time for this occurrence
  def when_text
    date_str = occurs_at.strftime('%B %d, %Y')
    time_str = occurs_at.strftime('%I:%M %p')
    "on #{date_str} at #{time_str}"
  end

  # Substitute {{when}} placeholder with actual date/time
  def substitute_when_placeholder(message)
    return message if message.blank?

    message.gsub(/\{\{when\}\}/i, when_text)
  end

  # Default short reminder message (for Bluesky - limited characters)
  def reminder_short_default(_days_ahead = nil)
    substitute_when_placeholder(event.reminder_short_default)
  end

  # Default long reminder message (for Slack/Instagram - more detail allowed)
  def reminder_long_default(_days_ahead = nil)
    base = substitute_when_placeholder(event.reminder_long_default)
    duration_str = format_duration_text(duration)

    # Add occurrence-specific details
    details = "\n📅 #{occurs_at.strftime('%B %d, %Y')} at #{occurs_at.strftime('%I:%M %p')} (#{duration_str})"
    details += "\n📍 #{event_location.name}" if event_location.present?

    "#{base}#{details}"
  end

  # Get the effective 7-day short reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_7d_short
    message = reminder_7d_short.presence || event.reminder_7d_short
    substitute_when_placeholder(message)
  end

  # Get the effective 1-day short reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_1d_short
    message = reminder_1d_short.presence || event.reminder_1d_short
    substitute_when_placeholder(message)
  end

  # Get the effective 7-day long reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_7d_long
    message = reminder_7d_long.presence || event.reminder_7d_long
    substitute_when_placeholder(message)
  end

  # Get the effective 1-day long reminder (own or inherited from event, with {{when}} substituted)
  def effective_reminder_1d_long
    message = reminder_1d_long.presence || event.reminder_1d_long
    substitute_when_placeholder(message)
  end

  after_update :log_update
  after_save :log_banner_change

  attr_accessor :current_user_for_journal

  # Get the actual description (custom or inherited from event)
  def description
    custom_description.presence || event.description
  end

  # Get the actual duration (override or inherited from event)
  def duration
    duration_override || event.duration
  end

  # Get the banner image (own or inherited from event)
  def banner
    banner_image.attached? ? banner_image : event.banner_image
  end

  # Get the location (own or inherited from event)
  def event_location
    location || event.location
  end

  # Mark occurrence as postponed
  def postpone!(until_date, reason = nil, user = nil)
    self.current_user_for_journal = user if user

    Rails.logger.info "Postponing occurrence ##{id} from #{occurs_at} to #{until_date}"

    result = update(status: 'postponed', postponed_until: until_date, cancellation_reason: reason)

    if result
      Rails.logger.info "Successfully marked occurrence ##{id} as postponed"

      # Create new occurrence at the postponed date/time
      begin
        new_occurrence = event.occurrences.create!(
          occurs_at: until_date,
          status: 'active'
        )

        Rails.logger.info "✓ Created new active occurrence ##{new_occurrence.id} at #{until_date} for event ##{event.id}"
        Rails.logger.info "  - New occurrence status: #{new_occurrence.status}"
        Rails.logger.info "  - New occurrence occurs_at: #{new_occurrence.occurs_at}"
        Rails.logger.info "  - Event now has #{event.occurrences.count} total occurrences"

        # Log both the postponement and new occurrence creation
        log_status_change('postponed', reason, user) if user
      rescue StandardError => e
        Rails.logger.error "✗ Failed to create new occurrence: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise
      end
    else
      Rails.logger.error "Failed to mark occurrence ##{id} as postponed: #{errors.full_messages.join(', ')}"
    end

    result
  end

  # Mark occurrence as cancelled
  def cancel!(reason = nil, user = nil)
    self.current_user_for_journal = user if user
    result = update(status: 'cancelled', cancellation_reason: reason)
    log_status_change('cancelled', reason, user) if result && user
    result
  end

  # Mark occurrence as relocated
  def relocate!(new_location, reason = nil, user = nil)
    self.current_user_for_journal = user if user
    result = update(status: 'relocated', relocated_to: new_location, cancellation_reason: reason)
    log_status_change('relocated', reason, user) if result && user
    result
  end

  # Reactivate occurrence
  def reactivate!(user = nil)
    self.current_user_for_journal = user if user
    result = update(status: 'active', postponed_until: nil, cancellation_reason: nil, relocated_to: nil)
    log_status_change('reactivated', nil, user) if result && user
    result
  end

  # Display name for this occurrence
  def name
    "#{event.title} - #{occurs_at.strftime('%B %d, %Y')}"
  end

  private

  def format_duration_text(minutes)
    hours = minutes / 60
    mins = minutes % 60
    if hours.positive? && mins.positive?
      "#{hours}h #{mins}m"
    elsif hours.positive?
      "#{hours} hour#{'s' if hours > 1}"
    else
      "#{mins} minutes"
    end
  end

  def generate_slug
    return if slug.present?

    assign_unique_slug_from_occurs_at
  end

  def assign_unique_slug_from_occurs_at
    return if event.blank? || occurs_at.blank?

    event_slug = event.title.parameterize
    date_slug = occurs_at.strftime('%Y-%m-%d')
    base_slug = "#{event_slug}-#{date_slug}"
    new_slug = base_slug
    counter = 1

    conflict_scope = EventOccurrence.unscoped
    conflict_scope = conflict_scope.where.not(id: id) if persisted?

    # Check against ALL occurrences including soft-deleted ones to avoid conflicts
    while conflict_scope.exists?(slug: new_slug)
      new_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = new_slug
  end

  def rename_banner_image
    return unless banner_image.attached?
    return unless banner_image.blob.persisted? == false || banner_image.attachment&.new_record?

    blob = banner_image.blob
    extension = File.extname(blob.filename.to_s)
    timestamp = Time.current.to_i
    new_filename = "#{slug || "#{event.title.parameterize}-#{occurs_at.strftime('%Y-%m-%d')}"}-banner-#{timestamp}#{extension}"

    blob.filename = new_filename
  end

  def log_update
    return unless current_user_for_journal
    return unless saved_changes.any?

    tracked_changes = {}
    saved_changes.each do |key, (old_val, new_val)|
      next if %w[updated_at created_at].include?(key)

      tracked_changes[key] = { 'from' => old_val, 'to' => new_val }
    end

    return if tracked_changes.empty?

    EventJournal.log_occurrence_change(
      self,
      current_user_for_journal,
      'updated',
      tracked_changes
    )
  end

  def log_status_change(action, reason, user)
    return unless user

    changes_data = { 'status' => action }
    changes_data['reason'] = reason if reason.present?

    EventJournal.log_occurrence_change(
      self,
      user,
      action,
      changes_data
    )
  end

  def log_banner_change
    return unless current_user_for_journal
    return if new_record?

    # Check if banner was added
    return unless banner_image.attached? && banner_image.attachment.blob.created_at > 5.seconds.ago

    EventJournal.log_occurrence_change(
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

end
