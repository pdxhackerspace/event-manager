# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SocialService do
  let(:event) { create(:event) }
  let(:occurrence) { create(:event_occurrence, event: event) }

  before do
    allow(ENV).to receive(:fetch).with('RAILS_HOST', anything).and_return('example.com')
    allow(ENV).to receive(:fetch).with('RAILS_PROTOCOL', anything).and_return('https')
    allow(ENV).to receive(:fetch).with('HOST', anything).and_return('example.com')
  end

  describe '.post_instagram' do
    before do
      allow(SocialCredential).to receive(:get_token).with('instagram').and_return('test_token')
      allow(ENV).to receive(:fetch).with('INSTAGRAM_ACCOUNT_ID', nil).and_return('12345')
      allow(ENV).to receive(:fetch).with('INSTAGRAM_ACCESS_TOKEN', nil).and_return(nil)
    end

    context 'when not configured' do
      before do
        allow(SocialCredential).to receive(:get_token).with('instagram').and_return(nil)
        allow(ENV).to receive(:fetch).with('INSTAGRAM_ACCESS_TOKEN', nil).and_return(nil)
      end

      it 'returns error' do
        result = described_class.post_instagram('Test message')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Not configured')
      end
    end

    context 'when image is not provided' do
      it 'returns error' do
        result = described_class.post_instagram('Test message')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Image required')
      end
    end

    context 'when configured with image' do
      let(:http_mock) { instance_double(Net::HTTP) }
      let(:container_response) do
        instance_double(Net::HTTPSuccess, body: '{"id": "container123"}', is_a?: ->(klass) { klass == Net::HTTPSuccess })
      end
      let(:status_response) do
        instance_double(Net::HTTPSuccess, body: '{"status_code": "FINISHED"}', is_a?: ->(klass) { klass == Net::HTTPSuccess })
      end
      let(:publish_response) do
        instance_double(Net::HTTPSuccess, body: '{"id": "post123"}', is_a?: ->(klass) { klass == Net::HTTPSuccess })
      end

      before do
        allow(Net::HTTP).to receive(:start).and_return(container_response, publish_response)
        allow(Net::HTTP).to receive(:get_response).and_return(status_response)
      end

      it 'creates container and publishes' do
        result = described_class.post_instagram('Test', image_url: 'https://example.com/image.jpg')

        expect(result[:success]).to be true
      end
    end
  end

  describe '.post_bluesky' do
    let(:bluesky_handle) { 'test.bsky.social' }
    let(:bluesky_password) { 'test_app_password' }

    before do
      allow(ENV).to receive(:fetch).with('BLUESKY_HANDLE', nil).and_return(bluesky_handle)
      allow(ENV).to receive(:fetch).with('BLUESKY_APP_PASSWORD', nil).and_return(bluesky_password)
    end

    context 'when not configured' do
      before do
        allow(ENV).to receive(:fetch).with('BLUESKY_HANDLE', nil).and_return(nil)
      end

      it 'returns error' do
        result = described_class.post_bluesky('Test message')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Not configured')
      end
    end

    context 'when configured' do
      let(:session_response) do
        body = { 'did' => 'did:plc:test123', 'accessJwt' => 'jwt_token' }.to_json
        instance_double(Net::HTTPSuccess, body: body, is_a?: ->(klass) { klass == Net::HTTPSuccess })
      end
      let(:post_response) do
        body = { 'uri' => 'at://did:plc:test123/post/123', 'cid' => 'cid123' }.to_json
        instance_double(Net::HTTPSuccess, body: body, is_a?: ->(klass) { klass == Net::HTTPSuccess })
      end

      before do
        allow(Net::HTTP).to receive(:start).and_return(session_response, post_response)
      end

      it 'creates session and posts' do
        result = described_class.post_bluesky('Test message')

        expect(result[:success]).to be true
        expect(result[:post_url]).to include('bsky.app')
      end
    end
  end

  describe '.post_occurrence_reminder' do
    let(:short_parts) { { text: 'Short message', link_url: 'https://example.com', link_text: 'More' } }
    let(:long_parts) { { text: 'Long message with details', link_url: 'https://example.com', link_text: 'More' } }

    before do
      # Mock both services to return success
      allow(described_class).to receive_messages(post_bluesky: { success: true, post_uid: 'uid1', post_url: 'https://bsky.app/1' }, post_instagram: { success: true, post_id: 'id1' })
    end

    it 'posts to both platforms' do
      expect(described_class).to receive(:post_bluesky)
      expect(described_class).to receive(:post_instagram)

      described_class.post_occurrence_reminder(occurrence, short_parts: short_parts, long_parts: long_parts)
    end

    it 'records posting for successful platforms' do
      expect do
        described_class.post_occurrence_reminder(occurrence, short_parts: short_parts, long_parts: long_parts,
                                                             reminder_type: '6 days')
      end.to change(ReminderPosting, :count).by(2)
    end

    it 'sets reminder_type on posting records' do
      described_class.post_occurrence_reminder(occurrence, short_parts: short_parts, long_parts: long_parts,
                                                           reminder_type: '6 days')

      postings = ReminderPosting.last(2)
      expect(postings.map(&:reminder_type)).to all(eq('6 days'))
    end

    it 'returns true if any platform succeeds' do
      allow(described_class).to receive(:post_instagram).and_return({ success: false })

      result = described_class.post_occurrence_reminder(occurrence, short_parts: short_parts, long_parts: long_parts)

      expect(result).to be true
    end

    context 'when both platforms fail' do
      before do
        allow(described_class).to receive_messages(post_bluesky: { success: false }, post_instagram: { success: false })
      end

      it 'returns false' do
        result = described_class.post_occurrence_reminder(occurrence, short_parts: short_parts, long_parts: long_parts)

        expect(result).to be false
      end
    end
  end

  describe '.record_posting' do
    it 'creates ReminderPosting with correct attributes' do
      described_class.send(:record_posting, occurrence, 'Test message', platform: 'bluesky',
                                                                        reminder_type: '6 days',
                                                                        post_uid: 'uid123',
                                                                        post_url: 'https://example.com/post')

      posting = ReminderPosting.last
      expect(posting.event).to eq(event)
      expect(posting.event_occurrence).to eq(occurrence)
      expect(posting.platform).to eq('bluesky')
      expect(posting.message).to eq('Test message')
      expect(posting.reminder_type).to eq('6 days')
      expect(posting.post_uid).to eq('uid123')
      expect(posting.post_url).to eq('https://example.com/post')
    end
  end

  describe '.banner_url_for' do
    context 'when occurrence has banner' do
      let(:occurrence) { create(:event_occurrence, :with_banner, event: event) }

      it 'returns occurrence banner URL' do
        url = described_class.send(:banner_url_for, occurrence)

        expect(url).to include('active_storage')
      end
    end

    context 'when only event has banner' do
      let(:event) { create(:event, :with_banner) }

      it 'returns event banner URL' do
        url = described_class.send(:banner_url_for, occurrence)

        expect(url).to include('active_storage')
      end
    end

    context 'when no banner attached' do
      it 'returns nil' do
        url = described_class.send(:banner_url_for, occurrence)

        expect(url).to be_nil
      end
    end
  end
end
