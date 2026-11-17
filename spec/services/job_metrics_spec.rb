# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobMetrics do
  let(:redis) { double('redis', hgetall: {}, pipelined: nil) }
  let(:pipe) { double('pipeline', hincrby: nil, hincrbyfloat: nil, hset: nil) }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(redis).to receive(:pipelined).and_yield(pipe)
  end

  describe '.record' do
    it 'counts the run, sums duration and fills cumulative buckets' do
      described_class.record('FooJob', 0.4)
      expect(pipe).to have_received(:hincrby).with(described_class::KEY, 'FooJob|count', 1)
      expect(pipe).to have_received(:hincrbyfloat).with(described_class::KEY, 'FooJob|duration_sum', 0.4)
      expect(pipe).to have_received(:hincrby).with(described_class::KEY, 'FooJob|bucket:0.5', 1)
      expect(pipe).not_to have_received(:hincrby).with(described_class::KEY, 'FooJob|bucket:0.1', 1)
      expect(pipe).not_to have_received(:hincrby).with(described_class::KEY, 'FooJob|failures', 1)
    end

    it 'counts failures' do
      described_class.record('FooJob', 0.4, failed: true)
      expect(pipe).to have_received(:hincrby).with(described_class::KEY, 'FooJob|failures', 1)
    end

    it 'never raises if Redis is unavailable' do
      allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError)
      expect { described_class.record('FooJob', 1) }.not_to raise_error
    end
  end

  describe '.snapshot' do
    it 'groups hash fields by job class' do
      allow(redis).to receive(:hgetall).and_return('A|count' => '2', 'A|failures' => '1', 'B|count' => '5')
      expect(described_class.snapshot).to eq('A' => { 'count' => '2', 'failures' => '1' }, 'B' => { 'count' => '5' })
    end
  end

  describe JobMetrics::Middleware do
    it 'records a successful job, preferring the wrapped ActiveJob class' do
      allow(described_class).to receive(:new).and_call_original
      allow(JobMetrics).to receive(:record)
      described_class.new.call(nil, { 'class' => 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper', 'wrapped' => 'FooJob' }, 'default') { :ok }
      expect(JobMetrics).to have_received(:record).with('FooJob', kind_of(Float), failed: false)
    end

    it 'records and re-raises failures' do
      allow(JobMetrics).to receive(:record)
      expect { described_class.new.call(nil, { 'class' => 'BarJob' }, 'default') { raise 'boom' } }.to raise_error('boom')
      expect(JobMetrics).to have_received(:record).with('BarJob', kind_of(Float), failed: true)
    end
  end
end
