require 'rails_helper'

RSpec.describe 'Trusted proxy configuration' do
  def ranges_for(env_value)
    if env_value.nil?
      ENV.delete('TRUSTED_PROXY_RANGES')
    else
      ENV['TRUSTED_PROXY_RANGES'] = env_value
    end

    EventManager::Application.trusted_proxy_ranges
  end

  around do |example|
    original = ENV.fetch('TRUSTED_PROXY_RANGES', nil)
    example.run
  ensure
    original.nil? ? ENV.delete('TRUSTED_PROXY_RANGES') : ENV['TRUSTED_PROXY_RANGES'] = original
  end

  describe 'TRUSTED_PROXY_RANGES' do
    it 'parses a comma separated list' do
      expect(ranges_for('10.1.0.0/16,192.0.2.7').map(&:to_s)).to eq(['10.1.0.0', '192.0.2.7'])
    end

    it 'tolerates surrounding whitespace' do
      expect(ranges_for(' 10.1.0.0/16 , 192.0.2.7 ').map(&:to_s)).to eq(['10.1.0.0', '192.0.2.7'])
    end

    # A stray comma is a formatting slip, not a decision, and previously took the
    # whole app down at boot.
    it 'skips empty entries rather than failing to boot' do
      ['10.1.0.0/16,', ',10.1.0.0/16', '10.1.0.0/16,,192.0.2.7', '10.1.0.0/16, ,192.0.2.7'].each do |value|
        expect { ranges_for(value) }.not_to raise_error, "expected #{value.inspect} to be accepted"
      end
    end

    it 'yields no extra ranges when every entry is empty' do
      expect(ranges_for(',')).to be_empty
      expect(ranges_for(' , ')).to be_empty
    end

    # Silently dropping a mistyped range would quietly widen rate limit buckets.
    it 'reports a malformed range, naming the offending value' do
      expect { ranges_for('10.1.0.0/16,not-an-ip') }
        .to raise_error(/Invalid trusted proxy range "not-an-ip".*TRUSTED_PROXY_RANGES/m)
    end

    it 'reports an out of range prefix' do
      expect { ranges_for('10.0.0.0/99') }.to raise_error(%r{Invalid trusted proxy range "10\.0\.0\.0/99"})
    end
  end

  describe 'config/trusted_proxies.yml' do
    subject(:ranges) { ranges_for(nil) }

    def trusts?(ranges, address)
      ranges.any? { |range| range.include?(IPAddr.new(address)) }
    end

    it 'is used when the environment variable is unset' do
      expect(ranges).to be_present
      expect(ranges).to all(be_a(IPAddr))
    end

    it 'covers the Cloudflare edge ranges rate limiting depends on' do
      aggregate_failures do
        %w[104.16.5.5 172.64.0.1 131.0.72.1 2606:4700::1].each do |address|
          expect(trusts?(ranges, address)).to be(true), "expected #{address} to be trusted"
        end
      end
    end

    it 'does not trust ordinary visitor addresses' do
      aggregate_failures do
        ['203.0.113.77', '8.8.8.8'].each do |address|
          expect(trusts?(ranges, address)).to be(false), "expected #{address} to be untrusted"
        end
      end
    end
  end
end
