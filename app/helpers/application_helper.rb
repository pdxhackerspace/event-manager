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
  def safe_url(url)
    return nil if url.blank?

    uri = URI.parse(url)
    return url if uri.scheme.in?(%w[http https])

    nil
  rescue URI::InvalidURIError
    nil
  end
end
