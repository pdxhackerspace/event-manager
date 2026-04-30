class SiteConfig < ApplicationRecord
  DEFAULT_AI_REMINDER_PROMPT = "Create a short, friendly reminder for {{event_title}} happening on {{event_date}} at {{event_time}} at PDX Hackerspace.".freeze

  has_one_attached :favicon
  has_one_attached :banner_image

  validates :organization_name, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email" },
                            allow_blank: true
  validates :website_url,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL (starting with http:// or https://)" }, allow_blank: true
  validates :ai_url,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL (starting with http:// or https://)" }, allow_blank: true

  # Singleton pattern - only one site config should exist with id = 1
  # Uses find_or_create_by! for atomic operation with smaller race window
  def self.instance
    find_or_create_by!(id: 1) do |config|
      config.organization_name = 'EventManager'
    end
  rescue ActiveRecord::RecordNotUnique
    # Another process created the record - just find it
    find(1)
  end

  def self.current
    instance
  end

  def ai_reminder_prompt_with_default
    ai_reminder_prompt.presence || DEFAULT_AI_REMINDER_PROMPT
  end
end
