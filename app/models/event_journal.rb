class EventJournal < ApplicationRecord
  belongs_to :event, optional: true  # Optional so journals persist after event deletion
  belongs_to :user, optional: true   # Optional so journals persist after user deletion
  belongs_to :occurrence, class_name: 'EventOccurrence', optional: true

  validates :action, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  # Log an event change
  def self.log_event_change(event, user, action, changed_attributes = {})
    create!(
      event: event,
      user: user,
      action: action,
      change_data: changed_attributes
    )
  end

  # Log an occurrence change
  def self.log_occurrence_change(occurrence, user, action, changed_attributes = {})
    create!(
      event: occurrence.event,
      user: user,
      action: action,
      occurrence_id: occurrence.id,
      change_data: changed_attributes
    )
  end

  # Human-readable change summary
  def summary
    case action
    when 'created' then created_summary
    when 'updated' then updated_summary
    when 'cancelled' then status_summary('Cancelled')
    when 'postponed' then status_summary('Postponed')
    when 'reactivated' then status_summary('Reactivated')
    when 'deleted' then status_summary('Deleted')
    when 'host_added' then "Added #{change_data['added_host']} as co-host"
    when 'host_removed' then "Removed #{change_data['removed_host']} as co-host"
    when 'banner_added' then banner_added_summary
    when 'banner_removed' then banner_removed_summary
    when 'images_added' then images_added_summary
    when 'image_removed' then image_removed_summary
    when 'images_reordered' then 'Reordered image pool'
    when 'images_reassigned' then images_reassigned_summary
    when 'image_updated' then 'Updated pool image settings'
    else action.titleize
    end
  end

  # Get formatted changes for display
  def formatted_changes
    return {} if change_data.blank?

    change_data.transform_keys do |key|
      key.to_s.titleize
    end
  end

  private

  def created_summary
    occurrence_id ? "Created occurrence for #{occurrence_date}" : 'Created event'
  end

  def updated_summary
    if change_data.present?
      changed_fields = change_data.keys.join(', ')
      occurrence_id ? "Updated occurrence (#{changed_fields})" : "Updated event (#{changed_fields})"
    else
      occurrence_id ? 'Updated occurrence' : 'Updated event'
    end
  end

  def status_summary(verb)
    occurrence_id ? "#{verb} occurrence for #{occurrence_date}" : "#{verb} event"
  end

  def banner_added_summary
    if change_data['banner_image'].present?
      filename = change_data['banner_image']['filename']
      size = change_data['banner_image']['size']
      occurrence_id ? "Added banner image to occurrence: #{filename} (#{size})" : "Added banner image: #{filename} (#{size})"
    else
      occurrence_id ? 'Added banner image to occurrence' : 'Added banner image'
    end
  end

  def banner_removed_summary
    occurrence_id ? 'Removed banner image from occurrence' : 'Removed banner image'
  end

  def images_added_summary
    count = change_data['count']
    count ? "Added #{count} #{'image'.pluralize(count.to_i)} to the pool" : 'Added images to the pool'
  end

  def image_removed_summary
    change_data['filename'].present? ? "Removed image from pool: #{change_data['filename']}" : 'Removed image from pool'
  end

  def images_reassigned_summary
    count = change_data['count']
    mode = change_data['mode']
    if count && mode
      "Reassigned images for #{count} #{'occurrence'.pluralize(count.to_i)} using #{mode} mode"
    else
      'Reassigned occurrence images from pool'
    end
  end

  def occurrence_date
    occurrence&.occurs_at&.strftime('%B %d, %Y') || 'Unknown date'
  end
end
