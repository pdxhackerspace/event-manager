# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Metrics', type: :request do
  let(:token) { 'secret-metrics-token' }
  let(:auth) { { 'Authorization' => "Bearer #{token}" } }

  around do |example|
    original = ENV.fetch('METRICS_TOKEN', nil)
    example.run
  ensure
    ENV['METRICS_TOKEN'] = original
  end

  context 'when METRICS_TOKEN is not configured' do
    before { ENV['METRICS_TOKEN'] = nil }

    it 'returns 404 even with a header' do
      get '/metrics', headers: auth
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when METRICS_TOKEN is configured' do
    before do
      ENV['METRICS_TOKEN'] = token
      allow(JobMetrics).to receive(:snapshot).and_return(
        'RsvpOfferJob' => { 'count' => '4', 'failures' => '1', 'duration_sum' => '2.5',
                            'last_run' => '1700000000.0', 'bucket:0.1' => '1', 'bucket:1' => '3', 'bucket:5' => '4' }
      )
      stats = instance_double(Sidekiq::Stats, processed: 10, failed: 2, workers_size: 1, processes_size: 1,
                                              scheduled_size: 0, retry_size: 1, dead_size: 0, enqueued: 3,
                                              queues: { 'default' => 3 })
      allow(Sidekiq::Stats).to receive(:new).and_return(stats)
      allow(Sidekiq::Queue).to receive(:all).and_return([instance_double(Sidekiq::Queue, name: 'default', latency: 1.5)])
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(
        [{ 'concurrency' => 5, 'busy' => 1, 'hostname' => 'worker-1', 'pid' => 42, 'started_at' => 1_700_000_000 }]
      )
      [Sidekiq::RetrySet, Sidekiq::DeadSet, Sidekiq::ScheduledSet].each do |set|
        entries = set == Sidekiq::RetrySet ? [instance_double(Sidekiq::SortedEntry, display_class: 'RsvpOfferJob')] : []
        allow(set).to receive(:new).and_return(entries)
      end
    end

    it 'rejects a missing token' do
      get '/metrics'
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['WWW-Authenticate']).to include('Bearer')
    end

    it 'rejects a wrong token' do
      get '/metrics', headers: { 'Authorization' => 'Bearer nope' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not accept the token as a query parameter' do
      get '/metrics', params: { token: token }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'serves Prometheus text with a valid token' do
      create(:user)
      get '/metrics', headers: auth
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with('text/plain; version=0.0.4')
      expect(response.body).to include('# TYPE event_manager_users gauge')
      expect(response.body).to match(/^event_manager_users\{role="user"\} 1$/)
    end

    it 'includes build, sidekiq and job metrics' do
      get '/metrics', headers: auth
      body = response.body
      expect(body).to include('event_manager_build_info{')
      expect(body).to include('event_manager_sidekiq_retry_jobs_by_class{job="RsvpOfferJob"} 1')
      expect(body).to include('event_manager_sidekiq_server_busy{hostname="worker-1",pid="42"} 1')
      expect(body).to include('event_manager_job_executions_total{job="RsvpOfferJob"} 4')
      expect(body).to include('event_manager_job_failures_total{job="RsvpOfferJob"} 1')
      expect(body).to include('event_manager_job_duration_seconds_bucket{job="RsvpOfferJob",le="+Inf"} 4')
      expect(body).to include('event_manager_job_duration_seconds_sum{job="RsvpOfferJob"} 2.5')
      expect(body).to include('event_manager_collector_up{collector="sidekiq"} 1')
    end

    it 'reports a failing collector instead of failing the scrape' do
      allow(Sidekiq::Stats).to receive(:new).and_raise(RedisClient::CannotConnectError)
      get '/metrics', headers: auth
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('event_manager_collector_up{collector="sidekiq"} 0')
      expect(response.body).to include('event_manager_collector_up{collector="database"} 1')
    end
  end
end
