require 'rails_helper'

RSpec.describe RegenerateEventOccurrencesJob, type: :job do
  around do |example|
    Time.use_zone('America/Los_Angeles') { example.run }
  end

  describe '#perform' do
    def build_drifted_occurrence
      event = create(:event,
                     :weekly,
                     status: 'active',
                     max_occurrences: 5,
                     start_time: Time.zone.local(2026, 3, 1, 18, 30, 0))
      occurrence = event.occurrences.order(:occurs_at).first
      event.occurrences.where.not(id: occurrence.id).destroy_all
      occurrence.update_column(:occurs_at, occurrence.occurs_at + 1.hour) # rubocop:disable Rails/SkipsModelValidations
      [event, occurrence]
    end

    it 'runs without errors' do
      expect {
        described_class.perform_now
      }.not_to raise_error
    end

    it 'processes recurring events' do
      # Create a weekly recurring event
      event = create(:event, recurrence_type: 'weekly', status: 'active', max_occurrences: 10)

      # Manually delete future occurrences to simulate running low
      event.occurrences.where('occurs_at > ?', 2.weeks.from_now).destroy_all

      initial_count = event.occurrences.reload.count

      # Run the job
      described_class.perform_now

      # Should have regenerated occurrences
      expect(event.occurrences.reload.count).to be >= initial_count
    end

    it 'does not process cancelled events' do
      cancelled_event = create(:event, recurrence_type: 'weekly', status: 'cancelled', max_occurrences: 5)
      initial_count = cancelled_event.occurrences.count

      described_class.perform_now

      expect(cancelled_event.occurrences.reload.count).to eq(initial_count)
    end

    it 'does not process one-time events' do
      one_time = create(:event, recurrence_type: 'once', status: 'active')
      initial_count = one_time.occurrences.count

      described_class.perform_now

      expect(one_time.occurrences.reload.count).to eq(initial_count)
    end

    it 'handles errors without crashing' do
      create(:event, recurrence_type: 'weekly', status: 'active')

      # Stub to raise error
      allow_any_instance_of(Event).to receive(:regenerate_future_occurrences!).and_raise(StandardError, 'Test error')

      # Should not raise error
      expect {
        described_class.perform_now
      }.not_to raise_error
    end

    it 'preserves occurrence id and slug while correcting local time' do
      event, occurrence = build_drifted_occurrence
      original_slug = occurrence.slug
      expected_hour = event.start_time.in_time_zone(Time.zone).hour
      local_date = occurrence.occurs_at.in_time_zone(Time.zone).to_date

      described_class.perform_now

      reloaded_occurrence = event.occurrences.find(occurrence.id)
      matching_local_date = event.occurrences.select do |occ|
        occ.occurs_at.in_time_zone(Time.zone).to_date == local_date
      end

      expect(reloaded_occurrence.slug).to eq(original_slug)
      expect(reloaded_occurrence.occurs_at.in_time_zone(Time.zone).hour).to eq(expected_hour)
      expect(matching_local_date.size).to eq(1)
    end
  end
end
