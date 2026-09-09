# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SocialMediaReminderJob, type: :job do
  include ActiveJob::TestHelper

  let(:site_config) { SiteConfig.current }

  before do
    ActiveJob::Base.queue_adapter = :test
    site_config.update!(social_reminders_enabled: true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RAILS_HOST', anything).and_return('example.com')
    allow(ENV).to receive(:fetch).with('RAILS_PROTOCOL', anything).and_return('https')
    allow(ENV).to receive(:fetch).with('HOST', anything).and_return('example.com')
  end

  describe '#perform' do
    context 'when social reminders are disabled' do
      before { site_config.update!(social_reminders_enabled: false) }

      it 'skips without processing' do
        expect(SocialPostReminderJob).not_to receive(:set)

        described_class.perform_now
      end
    end

    context 'with valid configuration' do
      let(:event) do
        create(:event, status: 'active', draft: false, visibility: 'public', social_reminders: true)
      end

      context 'with occurrence 6 days from now' do
        let!(:occurrence_6_days) do
          create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day, status: 'active')
        end

        it 'enqueues SocialPostReminderJob for 6-day reminder' do
          expect do
            described_class.perform_now
          end.to have_enqueued_job(SocialPostReminderJob)
        end

        it 'passes correct arguments to SocialPostReminderJob' do
          described_class.perform_now

          expect(SocialPostReminderJob).to have_been_enqueued.with(
            occurrence_6_days.id,
            '6 days',
            6
          )
        end
      end

      context 'with occurrence 1 day from now' do
        let!(:occurrence_1_day) do
          create(:event_occurrence, event: event, occurs_at: 1.day.from_now.middle_of_day, status: 'active')
        end

        it 'enqueues SocialPostReminderJob for 1-day reminder' do
          described_class.perform_now

          expect(SocialPostReminderJob).to have_been_enqueued.with(
            occurrence_1_day.id,
            '1 day',
            1
          )
        end
      end

      context 'with multiple occurrences' do
        # rubocop:disable RSpec/LetSetup
        let!(:occ1) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.change(hour: 10), status: 'active') }
        let!(:occ2) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.change(hour: 14), status: 'active') }
        # rubocop:enable RSpec/LetSetup

        it 'enqueues jobs with staggered delays' do
          described_class.perform_now

          jobs = enqueued_jobs.select { |j| j['job_class'] == 'SocialPostReminderJob' }
          expect(jobs.length).to eq(2)
        end
      end
    end

    # rubocop:disable-next RSpec/MultipleMemoizedHelpers
    context 'filtering occurrences' do
      let(:public_event) { create(:event, visibility: 'public', draft: false, social_reminders: true) }
      let(:members_event) { create(:event, visibility: 'members', draft: false, social_reminders: true) }
      let(:private_event) { create(:event, visibility: 'private', draft: false, social_reminders: true) }
      let(:draft_event) { create(:event, visibility: 'public', draft: true, social_reminders: true) }
      let(:no_social_event) { create(:event, visibility: 'public', draft: false, social_reminders: false) }

      let!(:public_occ) { create(:event_occurrence, event: public_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:members_occ) { create(:event_occurrence, event: members_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:private_occ) { create(:event_occurrence, event: private_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:draft_occ) { create(:event_occurrence, event: draft_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:no_social_occ) { create(:event_occurrence, event: no_social_event, occurs_at: 6.days.from_now.middle_of_day) }

      it 'includes public events' do
        described_class.perform_now
        expect(SocialPostReminderJob).to have_been_enqueued.with(public_occ.id, anything, anything)
      end

      it 'includes members events' do
        described_class.perform_now
        expect(SocialPostReminderJob).to have_been_enqueued.with(members_occ.id, anything, anything)
      end

      it 'excludes private events' do
        described_class.perform_now
        expect(SocialPostReminderJob).not_to have_been_enqueued.with(private_occ.id, anything, anything)
      end

      it 'excludes draft events' do
        described_class.perform_now
        expect(SocialPostReminderJob).not_to have_been_enqueued.with(draft_occ.id, anything, anything)
      end

      it 'excludes events with social_reminders disabled' do
        described_class.perform_now
        expect(SocialPostReminderJob).not_to have_been_enqueued.with(no_social_occ.id, anything, anything)
      end
    end
  end

  describe '#already_posted_today?' do
    let(:event) { create(:event, visibility: 'public', draft: false, social_reminders: true) }
    let(:occurrence) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day) }
    let(:job) { described_class.new }

    context 'when no posting exists' do
      it 'returns false' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be false
      end
    end

    context 'when bluesky posting exists for today with same reminder_type' do
      before do
        ReminderPosting.create!(
          event: event,
          event_occurrence: occurrence,
          platform: 'bluesky',
          reminder_type: '6 days',
          message: 'Test message',
          posted_at: Time.current
        )
      end

      it 'returns true' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be true
      end
    end

    context 'when instagram posting exists for today with same reminder_type' do
      before do
        ReminderPosting.create!(
          event: event,
          event_occurrence: occurrence,
          platform: 'instagram',
          reminder_type: '6 days',
          message: 'Test message',
          posted_at: Time.current
        )
      end

      it 'returns true' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be true
      end
    end

    context 'when slack posting exists (different platform)' do
      before do
        ReminderPosting.create!(
          event: event,
          event_occurrence: occurrence,
          platform: 'slack',
          reminder_type: '6 days',
          message: 'Test message',
          posted_at: Time.current
        )
      end

      it 'returns false' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be false
      end
    end

    context 'when posting exists with different reminder_type' do
      before do
        ReminderPosting.create!(
          event: event,
          event_occurrence: occurrence,
          platform: 'bluesky',
          reminder_type: '1 day',
          message: 'Test message',
          posted_at: Time.current
        )
      end

      it 'returns false' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be false
      end
    end
  end

  describe '#format_duration' do
    let(:job) { described_class.new }

    it 'formats hours and minutes' do
      expect(job.send(:format_duration, 90)).to eq('1h 30m')
    end

    it 'formats hours only' do
      expect(job.send(:format_duration, 120)).to eq('2h')
    end

    it 'formats minutes only' do
      expect(job.send(:format_duration, 45)).to eq('45m')
    end
  end
end
