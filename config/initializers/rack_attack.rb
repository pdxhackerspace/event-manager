# Rack::Attack configuration for rate limiting
# https://github.com/rack/rack-attack

module Rack
  class Attack
    ### Configure Cache ###
    # Rack::Attack counters must be shared across Puma workers, otherwise each
    # worker enforces its own independent limits. Use Redis when available and
    # fall back to an in-process store for development and test.
    Rack::Attack.cache.store =
      if ENV['REDIS_URL'].present? && !Rails.env.local?
        ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch('REDIS_URL'), namespace: 'rack-attack')
      else
        ActiveSupport::Cache::MemoryStore.new
      end

    ### Client IP Resolution ###
    # Every throttle must key on the visitor. Behind Cloudflare plus a reverse
    # proxy, X-Forwarded-For arrives as "<visitor>, <cloudflare edge>" and
    # Rack::Request#ip returns the edge IP, which collapses all visitors into a
    # single shared bucket. Resolve the visitor explicitly instead.
    def self.client_ip(req)
      cloudflare_ip(req) || rails_remote_ip(req) || forwarded_client_ip(req) || req.ip
    end

    # Cloudflare overwrites this header at its edge, so it cannot be spoofed by
    # clients reaching us through Cloudflare.
    def self.cloudflare_ip(req)
      req.get_header('HTTP_CF_CONNECTING_IP').presence
    end

    # The value ActionDispatch::RemoteIp computed, when that middleware has
    # already run. It raises on inconsistent forwarding headers, and a throttle
    # discriminator is the wrong place to blow up, so treat that as unknown.
    def self.rails_remote_ip(req)
      req.get_header('action_dispatch.remote_ip')&.to_s.presence
    rescue ActionDispatch::RemoteIp::IpSpoofAttackError
      nil
    end

    # X-Forwarded-For is ordered client first, so the leftmost entry is the
    # visitor. Rack::Request#ip returns the *rightmost* untrusted entry instead,
    # which behind Cloudflare is an edge IP shared by many visitors.
    def self.forwarded_client_ip(req)
      req.get_header('HTTP_X_FORWARDED_FOR').to_s.split(',').first&.strip.presence
    end

    # Requests that never represent user intent and would otherwise consume the
    # general throttle budget: compiled assets, Active Storage image delivery
    # (a single image-heavy page can issue dozens of these), and health checks.
    UNTHROTTLED_PREFIXES = [
      '/assets',
      '/packs',
      '/rails/active_storage',
      '/health'
    ].freeze

    def self.unthrottled_path?(path)
      path.start_with?(*UNTHROTTLED_PREFIXES)
    end

    ### Safelist ###
    # Always allow requests from localhost (for development and health checks)
    safelist('allow-localhost') do |req|
      ['127.0.0.1', '::1'].include?(client_ip(req))
    end

    ### Throttle Authentication Endpoints ###

    # Limit sign-in attempts by IP address
    # 5 requests per 20 seconds
    throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
      client_ip(req) if req.path == '/users/sign_in' && req.post?
    end

    # Limit sign-in attempts by email parameter
    # 5 requests per 20 seconds per email
    throttle('logins/email', limit: 5, period: 20.seconds) do |req|
      if req.path == '/users/sign_in' && req.post?
        # Normalize email to prevent case-based bypasses
        req.params.dig('user', 'email')&.downcase&.strip
      end
    end

    # Limit OAuth callback attempts
    # 10 requests per minute
    throttle('oauth/ip', limit: 10, period: 1.minute) do |req|
      client_ip(req) if req.path.start_with?('/users/auth/')
    end

    # Limit password reset requests
    # 5 requests per hour per IP
    throttle('password_reset/ip', limit: 5, period: 1.hour) do |req|
      client_ip(req) if req.path == '/users/password' && req.post?
    end

    # Limit password reset by email
    # 3 requests per hour per email
    throttle('password_reset/email', limit: 3, period: 1.hour) do |req|
      req.params.dig('user', 'email')&.downcase&.strip if req.path == '/users/password' && req.post?
    end

    ### General API Rate Limiting ###

    # Limit all requests by IP (general protection)
    # 600 requests per 5 minutes, excluding assets and image delivery
    throttle('req/ip', limit: 600, period: 5.minutes) do |req|
      client_ip(req) unless unthrottled_path?(req.path)
    end

    ### Blocklist ###

    # Block requests with suspicious patterns (basic protection)
    blocklist('block-bad-actors') do |req|
      # Block requests trying to access common attack vectors
      Rack::Attack::Fail2Ban.filter("pentest-#{client_ip(req)}", maxretry: 3, findtime: 10.minutes, bantime: 1.hour) do
        # Detect scanning for vulnerabilities
        CGI.unescape(req.query_string).include?('etc/passwd') ||
          req.path.include?('wp-admin') ||
          req.path.include?('wp-login') ||
          req.path.include?('.php') ||
          req.path.include?('phpmyadmin')
      end
    end

    ### Custom Responses ###

    # Return 429 Too Many Requests with retry information
    self.throttled_responder = lambda do |request|
      match_data = request.env['rack.attack.match_data']
      now = match_data[:epoch_time]
      retry_after = match_data[:period] - (now % match_data[:period])

      headers = {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      }

      body = {
        error: 'Rate limit exceeded',
        retry_after: retry_after
      }.to_json

      [429, headers, [body]]
    end

    # Return 403 Forbidden for blocked requests
    self.blocklisted_responder = lambda do |_request|
      [403, { 'Content-Type' => 'text/plain' }, ['Forbidden']]
    end
  end
end

# Log throttled and blocked requests in development/production
ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn("[Rack::Attack] Throttled #{Rack::Attack.client_ip(req)} for #{req.path}")
end

ActiveSupport::Notifications.subscribe('blocklist.rack_attack') do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn("[Rack::Attack] Blocked #{Rack::Attack.client_ip(req)} for #{req.path}")
end
