# Sentry error tracking configuration
# Configure via environment variables:
#   SENTRY_DSN - The DSN from your Sentry project settings
#   SENTRY_ENVIRONMENT - Optional: Override the Rails environment name (defaults to Rails.env)

if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']

    # Set the environment (defaults to Rails.env)
    config.environment = ENV.fetch('SENTRY_ENVIRONMENT', Rails.env)

    # Set the release version if available
    config.release = ENV['APP_VERSION'] if ENV['APP_VERSION'].present?

    # Enable breadcrumbs for better context
    config.breadcrumbs_logger = %i[active_support_logger http_logger]

    # Sample rate for error events (1.0 = 100%)
    config.sample_rate = 1.0

    # Performance monitoring (tracing)
    # Set to a value between 0.0 and 1.0 to enable
    config.traces_sample_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', '0.1').to_f

    # Filter sensitive parameters
    config.send_default_pii = false

    # Exclude certain exceptions from being reported
    config.excluded_exceptions += [
      'ActionController::RoutingError',
      'ActiveRecord::RecordNotFound',
      'ActionController::InvalidAuthenticityToken'
    ]

    # Filter sensitive data from being sent
    config.before_send = lambda do |event, _hint|
      # Scrub sensitive headers
      if event.request&.headers
        event.request.headers.delete('Authorization')
        event.request.headers.delete('Cookie')
      end
      event
    end
  end

  Rails.logger.info "Sentry initialized for environment: #{Sentry.configuration.environment}"
else
  Rails.logger.info "Sentry not configured (SENTRY_DSN not set)"
end
