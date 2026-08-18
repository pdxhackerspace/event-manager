require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EventManager
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Set the application timezone from TZ environment variable
    # Falls back to Pacific Time (Portland, OR) if not set
    # Accepts both TZ database names (America/Los_Angeles) and Rails names (Pacific Time (US & Canada))
    config.time_zone = ENV.fetch('TZ', 'America/Los_Angeles')
    # Database stores times in UTC (recommended)
    config.active_record.default_timezone = :utc

    # Rails 8.1.3+ defaults to libvips; we use mini_magick (see Gemfile).
    config.active_storage.variant_processor = :mini_magick

    # Serve attachments through the proxy controller instead of the default
    # redirect controller. Redirect mode costs two round trips per image (a 302
    # plus the file itself) and returns short-lived, uncacheable URLs. Proxy URLs
    # are stable and sent with far-future public cache headers, so Cloudflare and
    # the browser can cache them and repeat page loads never reach Puma.
    config.active_storage.resolve_model_to_route = :rails_storage_proxy

    # Rails 7.1+ way to autoload lib directory
    # Ignore omniauth since directory name doesn't match module name (omniauth vs OmniAuth)
    config.autoload_lib(ignore: %w[assets tasks omniauth])

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
