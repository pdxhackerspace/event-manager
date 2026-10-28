class Rsvp < ApplicationRecord
  STATUSES = %w[pending confirmed waitlisted cancelled].freeze
  CANCELLED_VIA = %w[self host admin occurrence_cancelled].freeze

  belongs_to :event_occurrence
  belongs_to :user, optional: true
  belongs_to :cancelled_by, class_name: 'User', optional: true
  belongs_to :checked_in_by, class_name: 'User', optional: true

  has_secure_token :manage_token

  before_validation :normalize_contact

  validates :status, inclusion: { in: STATUSES }
  validates :cancelled_via, inclusion: { in: CANCELLED_VIA }, allow_nil: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, unless: :anonymized?
  validates :name, presence: true, unless: -> { anonymized? || user_id.present? }

  scope :active, -> { where.not(status: 'cancelled') }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :waitlisted, -> { where(status: 'waitlisted').order(:waitlisted_at, :id) }
  scope :guests, -> { where(user_id: nil) }
  scope :holding_spot, lambda {
    where(status: 'confirmed').or(where(status: 'waitlisted').where('offer_held_until > ?', Time.current))
  }

  def self.link_guest_rsvps!(user)
    return if user.email.blank?

    where(user_id: nil).where('LOWER(email) = ?', user.email.downcase).find_each do |rsvp|
      rsvp.update!(user: user)
      RsvpService.new(rsvp.event_occurrence).confirm_pending!(rsvp) if rsvp.status == 'pending'
    end
  end

  def display_name
    user&.username.presence || user&.name.presence || name.presence || 'Guest'
  end

  def anonymized?
    anonymized_at.present?
  end

  def holding_offer?(at = Time.current)
    status == 'waitlisted' && offer_held_until.present? && offer_held_until > at
  end

  def waitlist_position
    return nil unless status == 'waitlisted'

    event_occurrence.rsvps.waitlisted.where(
      'waitlisted_at < :at OR (waitlisted_at = :at AND rsvps.id <= :id)',
      at: waitlisted_at, id: id
    ).count
  end

  def confirmed?
    status == 'confirmed'
  end

  def waitlisted?
    status == 'waitlisted'
  end

  def pending?
    status == 'pending'
  end

  def cancelled?
    status == 'cancelled'
  end

  private

  def normalize_contact
    self.email = email.to_s.strip.downcase.presence
    self.name = name.to_s.strip.presence
  end
end
