# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

class SlackService
  class << self
    include Rails.application.routes.url_helpers

    def post_message(text, image_url: nil, image_alt: 'Event banner')
      webhook_url = ENV.fetch('SLACK_WEBHOOK_URL', nil)
      return { success: false, error: 'Webhook not configured' } if webhook_url.blank?

      payload = build_payload(text, image_url, image_alt)

      uri = URI.parse(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request.body = payload.to_json

      response = http.request(request)

      if response.code == '200'
        Rails.logger.info 'SlackService: Successfully posted message'
        { success: true }
      else
        Rails.logger.error "SlackService: Failed to post message. Response: #{response.code} #{response.body}"
        { success: false, error: "HTTP #{response.code}: #{response.body}" }
      end
    rescue StandardError => e
      Rails.logger.error "SlackService: Error posting message: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, error: e.message }
    end

    def post_occurrence_reminder(occurrence, message, reminder_type: nil)
      image_url = banner_url_for(occurrence)
      result = post_message(message, image_url: image_url, image_alt: occurrence.event.title)

      # Record the posting if successful
      record_posting(occurrence, message, reminder_type) if result[:success]

      result[:success]
    end

    private

    def record_posting(occurrence, message, reminder_type)
      ReminderPosting.create!(
        event: occurrence.event,
        event_occurrence: occurrence,
        platform: 'slack',
        message: message,
        reminder_type: reminder_type,
        posted_at: Time.current
        # NOTE: Slack webhooks don't return a message ID or URL
      )
    rescue StandardError => e
      Rails.logger.error "SlackService: Failed to record posting: #{e.message}"
    end

    def build_payload(text, image_url, image_alt)
      if image_url.present?
        {
          blocks: [
            {
              type: 'section',
              text: { type: 'mrkdwn', text: text },
              accessory: {
                type: 'image',
                image_url: image_url,
                alt_text: image_alt
              }
            }
          ],
          text: text # Fallback for notifications
        }
      else
        { text: text }
      end
    end

    def banner_url_for(occurrence)
      host = ENV.fetch('RAILS_HOST', ENV.fetch('HOST', 'localhost:3000'))
      protocol = ENV.fetch('RAILS_PROTOCOL', 'http')

      banner = occurrence.banner
      return rails_blob_url(banner, host: host, protocol: protocol) if banner.attached?

      nil
    end
  end
end
