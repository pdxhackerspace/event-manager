require 'rails_helper'

RSpec.describe 'Rack::Attack configuration' do
  subject(:rack_attack) { Rack::Attack }

  def request_for(env)
    Rack::Attack::Request.new({ 'REMOTE_ADDR' => '172.18.0.5', 'PATH_INFO' => '/events' }.merge(env))
  end

  describe '.client_ip' do
    it 'prefers the Cloudflare connecting IP' do
      req = request_for(
        'HTTP_CF_CONNECTING_IP' => '203.0.113.10',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.10, 198.51.100.7'
      )

      expect(rack_attack.client_ip(req)).to eq('203.0.113.10')
    end

    it 'uses the IP ActionDispatch::RemoteIp resolved when Cloudflare headers are absent' do
      req = request_for('action_dispatch.remote_ip' => '203.0.113.20')

      expect(rack_attack.client_ip(req)).to eq('203.0.113.20')
    end

    # Rack::Request#ip would return 198.51.100.7 here, bucketing every visitor
    # behind the reverse proxy together.
    it 'takes the leftmost forwarded entry rather than the proxy that appended itself' do
      req = request_for('HTTP_X_FORWARDED_FOR' => '203.0.113.30, 198.51.100.7')

      expect(rack_attack.client_ip(req)).to eq('203.0.113.30')
    end

    it 'falls back to the connecting address with no forwarding headers' do
      expect(rack_attack.client_ip(request_for({}))).to eq('172.18.0.5')
    end

    it 'treats a spoofed forwarding header as unknown instead of raising' do
      req = request_for(
        'HTTP_X_FORWARDED_FOR' => '203.0.113.40',
        'HTTP_CLIENT_IP' => '203.0.113.99',
        'action_dispatch.remote_ip' => ActionDispatch::RemoteIp::GetIp.new(
          ActionDispatch::Request.new(
            'HTTP_X_FORWARDED_FOR' => '203.0.113.40',
            'HTTP_CLIENT_IP' => '203.0.113.99',
            'REMOTE_ADDR' => '172.18.0.5'
          ),
          true,
          ActionDispatch::RemoteIp::TRUSTED_PROXIES
        )
      )

      expect(rack_attack.client_ip(req)).to eq('203.0.113.40')
    end
  end

  describe '.unthrottled_path?' do
    # Active Storage delivery is the reason image-heavy pages exhausted the
    # general per-IP budget and rendered broken images.
    it 'exempts Active Storage image delivery' do
      expect(rack_attack).to be_unthrottled_path('/rails/active_storage/representations/proxy/abc/def/banner.jpg')
      expect(rack_attack).to be_unthrottled_path('/rails/active_storage/blobs/proxy/abc/banner.jpg')
    end

    it 'exempts compiled assets and health checks' do
      expect(rack_attack).to be_unthrottled_path('/assets/application-abc123.css')
      expect(rack_attack).to be_unthrottled_path('/health/liveness')
    end

    it 'still counts ordinary page requests' do
      expect(rack_attack).not_to be_unthrottled_path('/events')
      expect(rack_attack).not_to be_unthrottled_path('/users/sign_in')
    end
  end
end
