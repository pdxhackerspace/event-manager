require_relative "boot"

require "ipaddr"
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

    # Proxies that sit in front of this app, from TRUSTED_PROXY_RANGES if set and
    # otherwise config/trusted_proxies.yml.
    def self.trusted_proxy_ranges
      configured = ENV['TRUSTED_PROXY_RANGES'].presence&.split(',') ||
                   YAML.load_file(File.expand_path('trusted_proxies.yml', __dir__))

      # An empty entry means a stray comma or an empty list item, which is a
      # formatting slip rather than a decision, so skip it instead of refusing to
      # boot. A malformed range is a genuine mistake that would quietly widen the
      # rate limit buckets, so report it, naming the value: IPAddr on its own says
      # only "invalid address:" with nothing after it.
      Array(configured).filter_map do |range|
        range = range.to_s.strip
        next if range.empty?

        IPAddr.new(range)
      rescue IPAddr::Error => e
        raise "Invalid trusted proxy range #{range.inspect}: #{e.message.strip.delete_suffix(':')}. " \
              'Check TRUSTED_PROXY_RANGES or config/trusted_proxies.yml.'
      end
    end

    # Requests arrive through Cloudflare and then a reverse proxy, each appending
    # itself to X-Forwarded-For. Listing those proxies is what lets
    # ActionDispatch::RemoteIp identify the visitor rather than the last hop: it
    # scans the header from the right and takes the first address that is not a
    # known proxy, so addresses a client forges sit to the left of the one
    # Cloudflare appends and can never be selected. Rate limiting keys on this.
    #
    # A custom list replaces Rails' defaults instead of extending them, so the
    # loopback and private ranges have to be carried over explicitly. Without
    # them a forged X-Forwarded-For entry could resolve to a loopback address.
    config.action_dispatch.trusted_proxies =
      ActionDispatch::RemoteIp::TRUSTED_PROXIES + trusted_proxy_ranges

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
