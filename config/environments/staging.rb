require "active_support/core_ext/integer/time"

# Same operational profile as production, but mail is captured via letter_opener_web
# (see Gemfile group :staging and routes mount at /letter_opener).
Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.assume_ssl = true

  config.cache_classes = true
  config.eager_load = true

  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  config.assets.compile = false

  config.active_storage.service = :local

  config.log_level = :info

  config.log_tags = [:request_id]

  config.action_mailer.perform_caching = false

  # Capture all mail in Letter Opener Web (browse at /letter_opener as an admin)
  config.action_mailer.delivery_method = :letter_opener_web
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  config.action_mailer.default_url_options = {
    host: ENV.fetch("RAILS_HOST", "localhost"),
    protocol: ENV.fetch("RAILS_PROTOCOL", "https")
  }

  config.i18n.fallbacks = true

  config.active_support.report_deprecations = false

  config.log_formatter = Logger::Formatter.new

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger           = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  config.active_record.dump_schema_after_migration = false
end
