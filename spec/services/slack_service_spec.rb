# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SlackService do
  let(:webhook_url) { 'https://hooks.slack.com/services/test/webhook' }

  before do
    allow(ENV).to receive(:fetch).with('SLACK_WEBHOOK_URL', nil).and_return(webhook_url)
    allow(ENV).to receive(:fetch).with('RAILS_HOST', anything).and_return('example.com')
    allow(ENV).to receive(:fetch).with('RAILS_PROTOCOL', anything).and_return('https')
    allow(ENV).to receive(:fetch).with('HOST', anything).and_return('example.com')
  end

  describe '.post_message' do
    context 'when webhook is not configured' do
      before do
        allow(ENV).to receive(:fetch).with('SLACK_WEBHOOK_URL', nil).and_return(nil)
      end

      it 'returns error' do
        result = described_class.post_message('Test message')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Webhook not configured')
      end
    end

    context 'when webhook is configured' do
      let(:http_mock) { instance_double(Net::HTTP) }
      let(:response_mock) { instance_double(Net::HTTPResponse, code: '200') }

      before do
        allow(Net::HTTP).to receive(:new).and_return(http_mock)
        allow(http_mock).to receive(:use_ssl=)
        allow(http_mock).to receive(:request).and_return(response_mock)
      end

      it 'sends POST request to webhook URL' do
        expect(http_mock).to receive(:request) do |request|
          expect(request).to be_a(Net::HTTP::Post)
          expect(request['Content-Type']).to eq('application/json')
          response_mock
        end

        described_class.post_message('Test message')
      end

      it 'returns success for 200 response' do
        result = described_class.post_message('Test message')

        expect(result[:success]).to be true
      end

      context 'with image URL' do
        it 'includes image block in payload' do
          expect(http_mock).to receive(:request) do |request|
            body = JSON.parse(request.body)
            expect(body['blocks']).to be_present
            expect(body['blocks'][0]['accessory']['type']).to eq('image')
            response_mock
          end

          described_class.post_message('Test', image_url: 'https://example.com/image.jpg')
        end
      end

      context 'without image URL' do
        it 'sends simple text payload' do
          expect(http_mock).to receive(:request) do |request|
            body = JSON.parse(request.body)
            expect(body['text']).to eq('Test message')
            expect(body['blocks']).to be_nil
            response_mock
          end

          described_class.post_message('Test message')
        end
      end
    end

    context 'when request fails' do
      let(:http_mock) { instance_double(Net::HTTP) }
      let(:response_mock) { instance_double(Net::HTTPResponse, code: '500', body: 'Server error') }

      before do
        allow(Net::HTTP).to receive(:new).and_return(http_mock)
        allow(http_mock).to receive(:use_ssl=)
        allow(http_mock).to receive(:request).and_return(response_mock)
      end

      it 'returns error with status code' do
        result = described_class.post_message('Test message')

        expect(result[:success]).to be false
        expect(result[:error]).to include('500')
      end
    end

    context 'when exception is raised' do
      before do
        allow(Net::HTTP).to receive(:new).and_raise(StandardError.new('Network error'))
      end

      it 'returns error with exception message' do
        result = described_class.post_message('Test message')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Network error')
      end
    end
  end

  describe '.post_occurrence_reminder' do
    let(:event) { create(:event) }
    let(:occurrence) { create(:event_occurrence, event: event) }
    let(:http_mock) { instance_double(Net::HTTP) }
    let(:response_mock) { instance_double(Net::HTTPResponse, code: '200') }

    before do
      allow(Net::HTTP).to receive(:new).and_return(http_mock)
      allow(http_mock).to receive(:use_ssl=)
      allow(http_mock).to receive(:request).and_return(response_mock)
    end

    it 'posts message and returns success status' do
      result = described_class.post_occurrence_reminder(occurrence, 'Test reminder')

      expect(result).to be true
    end

    it 'records posting on success' do
      expect do
        described_class.post_occurrence_reminder(occurrence, 'Test reminder', reminder_type: '6 days')
      end.to change(ReminderPosting, :count).by(1)
    end

    it 'sets reminder_type on posting record' do
      described_class.post_occurrence_reminder(occurrence, 'Test reminder', reminder_type: '6 days')

      posting = ReminderPosting.last
      expect(posting.reminder_type).to eq('6 days')
      expect(posting.platform).to eq('slack')
    end

    context 'when posting fails' do
      let(:response_mock) { instance_double(Net::HTTPResponse, code: '500', body: 'Error') }

      it 'does not record posting' do
        expect do
          described_class.post_occurrence_reminder(occurrence, 'Test reminder')
        end.not_to change(ReminderPosting, :count)
      end

      it 'returns false' do
        result = described_class.post_occurrence_reminder(occurrence, 'Test reminder')

        expect(result).to be false
      end
    end
  end

  describe '.build_payload' do
    it 'builds simple payload without image' do
      payload = described_class.send(:build_payload, 'Hello', nil, nil)

      expect(payload).to eq({ text: 'Hello' })
    end

    it 'builds block payload with image' do
      payload = described_class.send(:build_payload, 'Hello', 'https://img.jpg', 'Alt text')

      expect(payload[:blocks]).to be_present
      expect(payload[:blocks][0][:type]).to eq('section')
      expect(payload[:blocks][0][:text][:text]).to eq('Hello')
      expect(payload[:blocks][0][:accessory][:image_url]).to eq('https://img.jpg')
      expect(payload[:blocks][0][:accessory][:alt_text]).to eq('Alt text')
      expect(payload[:text]).to eq('Hello') # Fallback
    end
  end

  describe '.banner_url_for' do
    let(:event) { create(:event) }
    let(:occurrence) { create(:event_occurrence, event: event) }

    context 'when occurrence has banner image' do
      let(:occurrence) { create(:event_occurrence, :with_banner, event: event) }

      it 'returns occurrence banner URL' do
        url = described_class.send(:banner_url_for, occurrence)

        expect(url).to include('example.com')
        expect(url).to include('active_storage')
      end
    end

    context 'when only event has banner image' do
      let(:event) { create(:event, :with_banner) }

      it 'returns event banner URL' do
        url = described_class.send(:banner_url_for, occurrence)

        expect(url).to include('example.com')
        expect(url).to include('active_storage')
      end
    end

    context 'when no banner is attached' do
      it 'returns nil' do
        url = described_class.send(:banner_url_for, occurrence)

        expect(url).to be_nil
      end
    end
  end
end
