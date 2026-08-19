require 'rails_helper'

RSpec.describe 'Rack::Attack configuration' do
  subject(:rack_attack) { Rack::Attack }

  let(:cloudflare_edge) { '104.16.5.5' }
  let(:reverse_proxy) { '172.18.0.5' }
  let(:visitor) { '203.0.113.77' }
  let(:forged) { '9.9.9.9' }

  def env_for(headers = {})
    Rack::MockRequest.env_for('http://example.com/events', headers)
  end

  # Runs the real ActionDispatch::RemoteIp middleware with the application's
  # actual trusted_proxies configuration, so these cover the end-to-end
  # resolution rather than a stubbed value.
  def resolved_client_ip(headers = {})
    captured = nil
    app = lambda do |env|
      captured = Rack::Attack.client_ip(Rack::Attack::Request.new(env))
      [200, {}, []]
    end

    ActionDispatch::RemoteIp.new(
      app,
      Rails.application.config.action_dispatch.ip_spoofing_check,
      Rails.application.config.action_dispatch.trusted_proxies
    ).call(env_for(headers))

    captured
  end

  def safelisted?(headers = {})
    Rack::Attack.safelists['allow-localhost'].matched_by?(Rack::Attack::Request.new(env_for(headers)))
  end

  describe 'trusted proxies' do
    let(:proxies) { Rails.application.config.action_dispatch.trusted_proxies }

    it 'recognizes the Cloudflare edge as a proxy' do
      expect(proxies.any? { |range| range.include?(IPAddr.new(cloudflare_edge)) }).to be(true)
    end

    # A custom list replaces Rails' defaults rather than extending them. Losing
    # the loopback and private ranges would let a forged X-Forwarded-For entry
    # resolve to a loopback address.
    it "retains Rails' loopback and private ranges" do
      %w[127.0.0.1 ::1 10.0.0.9 172.18.0.5 192.168.1.9].each do |address|
        expect(proxies.any? { |range| range.include?(IPAddr.new(address)) }).to be(true), "expected #{address} trusted"
      end
    end
  end

  describe '.client_ip' do
    # Rack::Request#ip would return the Cloudflare edge address here, bucketing
    # every visitor behind that edge together.
    it 'resolves the visitor through a Cloudflare and reverse proxy chain' do
      ip = resolved_client_ip(
        'REMOTE_ADDR' => reverse_proxy,
        'HTTP_X_FORWARDED_FOR' => "#{visitor}, #{cloudflare_edge}"
      )

      expect(ip).to eq(visitor)
    end

    it 'ignores a forged CF-Connecting-IP header' do
      ip = resolved_client_ip(
        'REMOTE_ADDR' => reverse_proxy,
        'HTTP_CF_CONNECTING_IP' => forged,
        'HTTP_X_FORWARDED_FOR' => "#{visitor}, #{cloudflare_edge}"
      )

      expect(ip).to eq(visitor)
    end

    # Forged entries sit to the left of the address Cloudflare appends, and
    # resolution scans from the right, so they can never be selected.
    it 'ignores forged entries prepended to X-Forwarded-For' do
      ip = resolved_client_ip(
        'REMOTE_ADDR' => reverse_proxy,
        'HTTP_X_FORWARDED_FOR' => "#{forged}, 127.0.0.1, #{visitor}, #{cloudflare_edge}"
      )

      expect(ip).to eq(visitor)
    end

    it 'attributes a request that reaches the proxy directly to its real address' do
      ip = resolved_client_ip(
        'REMOTE_ADDR' => reverse_proxy,
        'HTTP_X_FORWARDED_FOR' => "127.0.0.1, #{visitor}"
      )

      expect(ip).to eq(visitor)
    end

    it 'still counts requests with contradictory forwarding headers' do
      ip = resolved_client_ip(
        'REMOTE_ADDR' => reverse_proxy,
        'HTTP_CLIENT_IP' => forged,
        'HTTP_X_FORWARDED_FOR' => "#{visitor}, #{cloudflare_edge}"
      )

      expect(ip).to eq(reverse_proxy)
    end

    it 'uses the connecting address when nothing is forwarded' do
      expect(resolved_client_ip('REMOTE_ADDR' => visitor)).to eq(visitor)
    end
  end

  describe 'the localhost safelist' do
    it 'allows requests that actually originate on the host' do
      expect(safelisted?('REMOTE_ADDR' => '127.0.0.1')).to be(true)
      expect(safelisted?('REMOTE_ADDR' => '::1')).to be(true)
    end

    # Safelisting on a resolved or forwarded address would let anyone who can
    # reach the origin skip every throttle and blocklist.
    it 'cannot be reached by forging a loopback address in a header' do
      expect(safelisted?('REMOTE_ADDR' => reverse_proxy, 'HTTP_CF_CONNECTING_IP' => '127.0.0.1')).to be(false)
      expect(safelisted?('REMOTE_ADDR' => reverse_proxy, 'HTTP_X_FORWARDED_FOR' => '127.0.0.1')).to be(false)
      expect(safelisted?('REMOTE_ADDR' => visitor, 'HTTP_X_FORWARDED_FOR' => '127.0.0.1, ::1')).to be(false)
    end

    it 'does not allow ordinary remote requests' do
      expect(safelisted?('REMOTE_ADDR' => visitor)).to be(false)
    end
  end

  describe '.loopback?' do
    it 'recognizes loopback addresses in either family' do
      expect(rack_attack).to be_loopback('127.0.0.1')
      expect(rack_attack).to be_loopback('127.0.0.53')
      expect(rack_attack).to be_loopback('::1')
      expect(rack_attack).to be_loopback('::ffff:127.0.0.1')
    end

    it 'rejects routable and unparseable addresses' do
      expect(rack_attack).not_to be_loopback(visitor)
      expect(rack_attack).not_to be_loopback('not-an-ip')
      expect(rack_attack).not_to be_loopback('')
      expect(rack_attack).not_to be_loopback(nil)
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
