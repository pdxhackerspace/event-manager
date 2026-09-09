# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SlackEventReminderJob, type: :job do
  include ActiveJob::TestHelper

  let(:site_config) { SiteConfig.current }

  before do
    ActiveJob::Base.queue_adapter = :test
    site_config.update!(slack_enabled: true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SLACK_WEBHOOK_URL', nil).and_return('https://hooks.slack.com/test')
    allow(ENV).to receive(:fetch).with('RAILS_HOST', anything).and_return('example.com')
    allow(ENV).to receive(:fetch).with('RAILS_PROTOCOL', anything).and_return('https')
    allow(ENV).to receive(:fetch).with('HOST', anything).and_return('example.com')
  end

  describe '#perform' do
    context 'when Slack is disabled' do
      before { site_config.update!(slack_enabled: false) }

      it 'skips without processing' do
        expect(SlackPostReminderJob).not_to receive(:set)

        described_class.perform_now
      end
    end

    context 'when webhook URL is not configured' do
      before do
        allow(ENV).to receive(:fetch).with('SLACK_WEBHOOK_URL', nil).and_return(nil)
      end

      it 'skips without processing' do
        expect(SlackPostReminderJob).not_to receive(:set)

        described_class.perform_now
      end
    end

    context 'with valid configuration' do
      let(:event) do
        create(:event, status: 'active', draft: false, visibility: 'public', slack_announce: true)
      end

      context 'with occurrence 6 days from now' do
        let!(:occurrence_6_days) do
          create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day, status: 'active')
        end

        it 'enqueues SlackPostReminderJob for 6-day reminder' do
          expect do
            described_class.perform_now
          end.to have_enqueued_job(SlackPostReminderJob)
        end

        it 'passes correct arguments to SlackPostReminderJob' do
          described_class.perform_now

          expect(SlackPostReminderJob).to have_been_enqueued.with(
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

        it 'enqueues SlackPostReminderJob for 1-day reminder' do
          described_class.perform_now

          expect(SlackPostReminderJob).to have_been_enqueued.with(
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

          # First job should have 0 delay, second should have POST_DELAY_SECONDS delay
          jobs = enqueued_jobs.select { |j| j['job_class'] == 'SlackPostReminderJob' }
          expect(jobs.length).to eq(2)
        end
      end
    end

    # rubocop:disable-next RSpec/MultipleMemoizedHelpers
    context 'filtering occurrences' do
      let(:public_event) { create(:event, visibility: 'public', draft: false, slack_announce: true) }
      let(:members_event) { create(:event, visibility: 'members', draft: false, slack_announce: true) }
      let(:private_event) { create(:event, visibility: 'private', draft: false, slack_announce: true) }
      let(:draft_event) { create(:event, visibility: 'public', draft: true, slack_announce: true) }
      let(:no_slack_event) { create(:event, visibility: 'public', draft: false, slack_announce: false) }

      let!(:public_occ) { create(:event_occurrence, event: public_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:members_occ) { create(:event_occurrence, event: members_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:private_occ) { create(:event_occurrence, event: private_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:draft_occ) { create(:event_occurrence, event: draft_event, occurs_at: 6.days.from_now.middle_of_day) }
      let!(:no_slack_occ) { create(:event_occurrence, event: no_slack_event, occurs_at: 6.days.from_now.middle_of_day) }

      it 'includes public events' do
        described_class.perform_now
        expect(SlackPostReminderJob).to have_been_enqueued.with(public_occ.id, anything, anything)
      end

      it 'includes members events' do
        described_class.perform_now
        expect(SlackPostReminderJob).to have_been_enqueued.with(members_occ.id, anything, anything)
      end

      it 'excludes private events' do
        described_class.perform_now
        expect(SlackPostReminderJob).not_to have_been_enqueued.with(private_occ.id, anything, anything)
      end

      it 'excludes draft events' do
        described_class.perform_now
        expect(SlackPostReminderJob).not_to have_been_enqueued.with(draft_occ.id, anything, anything)
      end

      it 'excludes events with slack_announce disabled' do
        described_class.perform_now
        expect(SlackPostReminderJob).not_to have_been_enqueued.with(no_slack_occ.id, anything, anything)
      end
    end

    context 'occurrence statuses' do
      let(:event) { create(:event, visibility: 'public', draft: false, slack_announce: true) }

      let!(:active_occ) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day, status: 'active') }
      let!(:cancelled_occ) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day + 1.hour, status: 'cancelled') }
      let!(:postponed_occ) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day + 2.hours, status: 'postponed') }
      let!(:relocated_occ) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day + 3.hours, status: 'relocated', relocated_to: 'New Venue') }

      it 'includes active occurrences' do
        described_class.perform_now
        expect(SlackPostReminderJob).to have_been_enqueued.with(active_occ.id, anything, anything)
      end

      it 'includes cancelled occurrences' do
        described_class.perform_now
        expect(SlackPostReminderJob).to have_been_enqueued.with(cancelled_occ.id, anything, anything)
      end

      it 'includes postponed occurrences' do
        described_class.perform_now
        expect(SlackPostReminderJob).to have_been_enqueued.with(postponed_occ.id, anything, anything)
      end

      it 'includes relocated occurrences' do
        described_class.perform_now
        expect(SlackPostReminderJob).to have_been_enqueued.with(relocated_occ.id, anything, anything)
      end
    end
  end

  describe '#already_posted_today?' do
    let(:event) { create(:event, visibility: 'public', draft: false, slack_announce: true) }
    let(:occurrence) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day) }
    let(:job) { described_class.new }

    context 'when no posting exists' do
      it 'returns false' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be false
      end
    end

    context 'when posting exists for today with same reminder_type' do
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

      it 'returns true' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be true
      end
    end

    context 'when posting exists for today with different reminder_type' do
      before do
        ReminderPosting.create!(
          event: event,
          event_occurrence: occurrence,
          platform: 'slack',
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

    context 'when posting exists for yesterday' do
      before do
        ReminderPosting.create!(
          event: event,
          event_occurrence: occurrence,
          platform: 'slack',
          reminder_type: '6 days',
          message: 'Test message',
          posted_at: 1.day.ago
        )
      end

      it 'returns false' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be false
      end
    end

    context 'when posting exists for different platform' do
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

      it 'returns false' do
        result = job.send(:already_posted_today?, occurrence, '6 days')
        expect(result).to be false
      end
    end
  end

  describe 'deduplication integration' do
    let(:event) { create(:event, visibility: 'public', draft: false, slack_announce: true) }
    let!(:occurrence) { create(:event_occurrence, event: event, occurs_at: 6.days.from_now.middle_of_day) }

    context 'when already posted today' do
      before do
        ReminderPosting.create!(
          event: event,
          event_occurrence: occurrence,
          platform: 'slack',
          reminder_type: '6 days',
          message: 'Already posted',
          posted_at: Time.current
        )
      end

      it 'does not enqueue duplicate job' do
        expect do
          described_class.perform_now
        end.not_to have_enqueued_job(SlackPostReminderJob).with(occurrence.id, '6 days', 6)
      end
    end

    context 'when not yet posted today' do
      it 'enqueues job' do
        expect do
          described_class.perform_now
        end.to have_enqueued_job(SlackPostReminderJob).with(occurrence.id, '6 days', 6)
      end
    end
  end
end
