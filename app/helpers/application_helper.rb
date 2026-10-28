module ApplicationHelper
  def authentik_configured?
    ENV['AUTHENTIK_CLIENT_ID'].present? &&
      ENV['AUTHENTIK_CLIENT_SECRET'].present? &&
      ENV['AUTHENTIK_SITE_URL'].present?
  end

  def can_create_events?
    user_signed_in? && (current_user.admin? || current_user.can_create_events?)
  end

  # Safely render a URL, ensuring it uses only http/https schemes
  # Returns nil if the URL is invalid or uses an unsafe scheme (e.g., javascript:)
  def formatted_event_description(source)
    html = EventDescription.for_display(source.rendered_description_html)
    return html if html.present?

    simple_format(source.description) if source.description.present?
  end

  # A plain String, so the RSS builder escapes the markup once. for_display
  # returns a safe buffer, and String.new drops that flag.
  def rss_description_markup(source)
    html = EventDescription.for_display(source.rendered_description_html)
    return String.new(html.to_s) if html.present?
    return if source.description.blank?

    "<p>#{source.description.truncate(500)}</p>"
  end

  def description_text_in_sync?(html, text)
    normalized = text.to_s.gsub("\r\n", "\n").strip
    HtmlToPlainText.call(html) == normalized
  end

  def safe_url(url)
    return nil if url.blank?

    uri = URI.parse(url)
    return url if uri.scheme.in?(%w[http https])

    nil
  rescue URI::InvalidURIError
    nil
  end
end
