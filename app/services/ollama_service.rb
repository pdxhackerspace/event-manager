# frozen_string_literal: true

require 'net/http'
require 'json'

class OllamaService
  class << self
    def available_models
      return [] unless configured?

      uri = ai_endpoint('/models')
      request = Net::HTTP::Get.new(uri)
      add_authorization_header(request)
      response = http_client(uri).request(request)

      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      models = data['data'] || []
      models.pluck('id').sort
    rescue StandardError => e
      Rails.logger.warn "OllamaService: Failed to fetch models: #{e.message}"
      []
    end

    def configured?
      ai_url.present?
    end

    def generate(prompt, model: nil)
      return nil unless configured?

      model ||= SiteConfig.current.ai_model.presence || 'gpt-4o-mini'

      Rails.logger.info "OllamaService: Generating with model '#{model}'"
      Rails.logger.debug { "OllamaService: Prompt: #{prompt.truncate(200)}" }

      uri = ai_endpoint('/chat/completions')
      http = http_client(uri)
      http.open_timeout = 10
      http.read_timeout = 60 # AI generation can take a while

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      add_authorization_header(request)
      request.body = {
        model: model,
        messages: [
          { role: 'user', content: prompt }
        ],
        stream: false
      }.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        generated_text = data.dig('choices', 0, 'message', 'content')&.strip
        Rails.logger.info "OllamaService: Generated #{generated_text&.length || 0} characters"
        generated_text
      else
        Rails.logger.error "OllamaService: Generation failed (#{response.code}) #{response.body.truncate(500)}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "OllamaService: Generation error - #{e.class}: #{e.message}"
      nil
    end

    # Generate a short reminder for an occurrence (for Bluesky)
    def generate_short_reminder(occurrence, days_ahead)
      generate_short_reminder_for_event(occurrence.event, days_ahead, occurrence.description)
    end

    # Generate a long reminder for an occurrence (for Slack/Instagram)
    def generate_long_reminder(occurrence, days_ahead)
      generate_long_reminder_for_event(occurrence.event, days_ahead, occurrence.description)
    end

    # Generate a short reminder for an event (for Bluesky)
    # Uses {{when}} as a placeholder for the date/time
    def generate_short_reminder_for_event(event, days_ahead, description = nil)
      return nil unless configured?

      site_config = SiteConfig.current
      max_length = site_config.short_reminder_max_length
      description ||= event.description

      prompt_template = site_config.ai_reminder_prompt_with_default
      base_prompt = build_base_prompt(prompt_template, event, description)

      full_prompt = build_short_prompt(base_prompt, max_length, days_ahead)
      clean_ai_response(generate(full_prompt))
    end

    # Generate a long reminder for an event (for Slack/Instagram)
    # Uses {{when}} as a placeholder for the date/time
    def generate_long_reminder_for_event(event, days_ahead, description = nil)
      return nil unless configured?

      site_config = SiteConfig.current
      max_length = site_config.long_reminder_max_length
      description ||= event.description

      prompt_template = site_config.ai_reminder_prompt_with_default
      base_prompt = build_base_prompt(prompt_template, event, description)

      full_prompt = build_long_prompt(base_prompt, max_length, days_ahead)
      clean_ai_response(generate(full_prompt))
    end

    # Legacy method - generates short reminder for backwards compatibility
    def generate_reminder(occurrence, days_ahead)
      generate_short_reminder(occurrence, days_ahead)
    end

    private

    def build_short_prompt(base_prompt, max_length, days_ahead)
      timing = days_ahead > 1 ? '6 days away' : 'tomorrow'
      <<~PROMPT
        #{base_prompt}

        Generate a short social media reminder for this event (#{timing}).

        STRICT REQUIREMENTS:
        - Output ONLY the reminder text. No introductions, no "Here is the reminder:", no explanations.
        - Maximum #{max_length - 20} characters (we need room for a link).
        - Use {{when}} as a placeholder for the date/time. Example: "Join us {{when}} at PDX Hackerspace!"
        - Do NOT include actual dates or times - only use {{when}}.
        - Mention the event name and PDX Hackerspace.
        - Be friendly and engaging.
        - No hashtags or emojis unless in the original description.

        Output the reminder text only:
      PROMPT
    end

    def build_long_prompt(base_prompt, max_length, days_ahead)
      timing = days_ahead > 1 ? '6 days away' : 'tomorrow'
      <<~PROMPT
        #{base_prompt}

        Generate a longer social media reminder for this event (#{timing}).

        STRICT REQUIREMENTS:
        - Output ONLY the reminder text. No introductions, no "Here is the reminder:", no explanations.
        - Maximum #{max_length} characters.
        - Use {{when}} as a placeholder for the date/time. Example: "Join us {{when}} at PDX Hackerspace!"
        - Do NOT include actual dates or times - only use {{when}}.
        - Include the event name, location, and mention PDX Hackerspace.
        - Include relevant details from the description.
        - Be friendly and engaging, encouraging attendance.
        - Line breaks are OK for readability.
        - No hashtags or emojis unless in the original description.

        Output the reminder text only:
      PROMPT
    end

    def build_base_prompt(prompt_template, event, description)
      prompt_template
        .gsub(/\{\{\s*event_title\s*\}\}/i, event.title)
        .gsub(/\{\{\s*event_description\s*\}\}/i, description.to_s)
    end

    # Clean up common AI response artifacts
    def clean_ai_response(response)
      return nil if response.blank?

      # Remove common AI framing phrases
      cleaned = response
                .gsub(/^["']|["']$/m, '') # Remove surrounding quotes
                .gsub(/^Here(?:'s| is) (?:the |a |your )?reminder:?\s*/i, '')
                .gsub(/^(?:Sure|OK|Okay)[,!.]?\s*(?:Here(?:'s| is)[^:]*:)?\s*/i, '')
                .gsub(/^Reminder:?\s*/i, '')
                .strip

      # If the cleaned response is empty, return the original
      cleaned.presence || response&.strip
    end

    def add_authorization_header(request)
      key = ai_key

      request['Authorization'] = "Bearer #{key}" if key.present?
    end

    def ai_endpoint(path)
      base_url = ai_url.chomp('/').sub(%r{/v1\z}, '')

      URI.parse("#{base_url}/v1#{path}")
    end

    def ai_key
      SiteConfig.current.ai_key.presence ||
        ENV.fetch('AI_API_KEY', nil).presence ||
        ENV.fetch('OLLAMA_API_KEY', nil)
    end

    def ai_url
      SiteConfig.current.ai_url.presence ||
        ENV.fetch('AI_SERVER_URL', nil).presence ||
        ENV.fetch('OLLAMA_SERVER', nil)
    end

    def http_client(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = uri.scheme == 'https'
      end
    end
  end
end
