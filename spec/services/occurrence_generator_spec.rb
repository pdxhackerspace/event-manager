# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OccurrenceGenerator do
  let(:la_zone) { Time.find_zone('America/Los_Angeles') }

  describe '#canonicalize_time' do
    let(:event) { create(:event, :weekly, start_time: la_zone.local(2025, 1, 7, 19, 0, 0)) }
    let(:generator) { described_class.new(event) }

    context 'with winter time (PST)' do
      it 'preserves the correct offset for winter dates' do
        # January is PST (UTC-8)
        winter_time = la_zone.local(2025, 1, 15, 19, 0, 0)
        canonical = generator.send(:canonicalize_time, winter_time)

        expect(canonical.utc_offset).to eq(-8 * 3600)
        expect(canonical.hour).to eq(19)
      end
    end

    context 'with summer time (PDT)' do
      it 'preserves the correct offset for summer dates' do
        # July is PDT (UTC-7)
        summer_time = la_zone.local(2025, 7, 15, 19, 0, 0)
        canonical = generator.send(:canonicalize_time, summer_time)

        expect(canonical.utc_offset).to eq(-7 * 3600)
        expect(canonical.hour).to eq(19)
      end
    end

    context 'when IceCube returns a time with stale DST offset' do
      it 're-anchors to the scheduled wall-clock time for the target date' do
        # Simulate IceCube returning 7 PM with PST offset for a summer date
        # This would display as 8 PM PDT - the bug we're fixing
        stale_time = Time.utc(2025, 6, 11, 3, 0, 0) # 7 PM PST = 3 AM UTC

        canonical = generator.send(:canonicalize_time, stale_time)

        # We always anchor to the event's intended local wall-clock time (7 PM)
        expect(canonical.in_time_zone(la_zone).hour).to eq(19)
        expect(canonical.utc_offset).to eq(-7 * 3600)
      end
    end
  end

  describe '#find_or_create_occurrence_by_date' do
    let(:event) { create(:event, :weekly, start_time: la_zone.local(2025, 1, 7, 19, 0, 0)) }
    let(:generator) { described_class.new(event) }

    before { event.occurrences.destroy_all }

    context 'when no occurrence exists for the date' do
      it 'builds a new occurrence with correct DST offset' do
        summer_time = la_zone.local(2025, 6, 10, 19, 0, 0)
        occ = generator.find_or_create_occurrence_by_date(summer_time, 'active')

        expect(occ).to be_new_record
        expect(occ.occurs_at.in_time_zone(la_zone).hour).to eq(19)
        expect(occ.occurs_at.utc_offset).to eq(-7 * 3600)
        expect(occ.status).to eq('active')
      end

      it 'uses the default status provided' do
        time = la_zone.local(2025, 6, 10, 19, 0, 0)
        occ = generator.find_or_create_occurrence_by_date(time, 'cancelled')

        expect(occ.status).to eq('cancelled')
      end
    end

    context 'when an occurrence exists with correct time' do
      let!(:existing_occ) do
        correct_time = la_zone.local(2025, 6, 10, 19, 0, 0)
        event.occurrences.create!(occurs_at: correct_time, status: 'active')
      end

      it 'returns the existing occurrence unchanged' do
        summer_time = la_zone.local(2025, 6, 10, 19, 0, 0)
        occ = generator.find_or_create_occurrence_by_date(summer_time, 'active')

        expect(occ.id).to eq(existing_occ.id)
        expect(occ).not_to be_changed
      end
    end

    context 'when an occurrence exists with wrong DST offset' do
      let!(:wrong_occ) do
        # 7 PM PST on a PDT date = wrong offset
        wrong_time = Time.utc(2025, 6, 11, 3, 0, 0) # 7 PM PST as UTC
        event.occurrences.create!(occurs_at: wrong_time, status: 'active')
      end

      it 'corrects the occurrence time' do
        correct_time = la_zone.local(2025, 6, 10, 19, 0, 0)
        occ = generator.find_or_create_occurrence_by_date(correct_time, 'active')

        expect(occ.id).to eq(wrong_occ.id)
        expect(occ.occurs_at.utc).to eq(correct_time.utc)
        expect(occ).to be_changed
      end

      it 'preserves the existing slug when correcting occurs_at' do
        correct_time = la_zone.local(2025, 6, 10, 19, 0, 0)
        original_slug = wrong_occ.slug

        occ = generator.find_or_create_occurrence_by_date(correct_time, 'active')
        occ.save!

        expect(occ.reload.slug).to eq(original_slug)
      end
    end

    context 'date matching across DST boundaries' do
      it 'finds occurrence by date even when times differ due to DST' do
        # Create occurrence at the edge of DST transition
        existing_time = la_zone.local(2025, 3, 9, 19, 0, 0) # DST starts March 9
        event.occurrences.create!(occurs_at: existing_time, status: 'active')

        # Query with same date, different time representation
        query_time = la_zone.local(2025, 3, 9, 19, 0, 0)
        occ = generator.find_or_create_occurrence_by_date(query_time, 'active')

        expect(occ).not_to be_new_record
      end
    end
  end

  describe '#update_occurrence_time_if_needed' do
    let(:event) { create(:event, :weekly, start_time: la_zone.local(2025, 1, 7, 19, 0, 0)) }
    let(:generator) { described_class.new(event) }

    context 'when occurrence time matches scheduled time' do
      it 'does not update the occurrence' do
        correct_time = la_zone.local(2025, 6, 10, 19, 0, 0)
        occ = event.occurrences.create!(occurs_at: correct_time, status: 'active')

        expect do
          generator.update_occurrence_time_if_needed(occ, correct_time)
        end.not_to(change { occ.reload.occurs_at })
      end
    end

    context 'when occurrence time has wrong DST offset' do
      it 'updates the occurrence to correct time' do
        wrong_time = Time.utc(2025, 6, 11, 3, 0, 0) # 7 PM PST as UTC (wrong for June)
        occ = event.occurrences.create!(occurs_at: wrong_time, status: 'active')

        correct_time = la_zone.local(2025, 6, 10, 19, 0, 0) # 7 PM PDT
        generator.update_occurrence_time_if_needed(occ, correct_time)

        expect(occ.reload.occurs_at.in_time_zone(la_zone).hour).to eq(19)
        expect(occ.occurs_at.utc_offset).to eq(-7 * 3600)
      end
    end
  end

  describe '#generate' do
    context 'for a one-time event' do
      let(:event) { create(:event, recurrence_type: 'once', start_time: 1.week.from_now) }
      let(:generator) { described_class.new(event) }

      before { event.occurrences.destroy_all }

      it 'creates exactly one occurrence' do
        generator.generate

        expect(event.occurrences.count).to eq(1)
      end

      it 'creates occurrence at the correct time' do
        generator.generate

        expect(event.occurrences.first.occurs_at.to_date).to eq(event.start_time.to_date)
      end
    end

    context 'for a weekly recurring event' do
      let(:event) { create(:event, :weekly, max_occurrences: 3, start_time: Time.current.beginning_of_week + 2.days + 19.hours) }
      let(:generator) { described_class.new(event) }

      before { event.occurrences.destroy_all }

      it 'creates up to max_occurrences' do
        generator.generate

        expect(event.occurrences.count).to be <= 3
      end

      it 'creates occurrences at the correct wall-clock time' do
        generator.generate

        event.occurrences.each do |occ|
          expect(occ.occurs_at.in_time_zone(Time.zone).hour).to eq(event.start_time.hour)
        end
      end
    end

    context 'when event is permanently cancelled' do
      let(:event) { create(:event, :weekly, permanently_cancelled: true) }
      let(:generator) { described_class.new(event) }

      before { event.occurrences.destroy_all }

      it 'does not generate occurrences' do
        generator.generate

        expect(event.occurrences.count).to eq(0)
      end
    end

    context 'when event is permanently relocated' do
      let(:event) do
        e = create(:event, :weekly)
        e.update!(permanently_relocated: true, relocated_to: 'New Venue')
        e
      end
      let(:generator) { described_class.new(event) }

      before do
        EventOccurrence.unscoped.where(event: event).delete_all
      end

      it 'does not generate occurrences' do
        generator.generate

        expect(event.occurrences.count).to eq(0)
      end
    end

    context 'when default_to_cancelled is true' do
      let(:event) { create(:event, :weekly, default_to_cancelled: true, max_occurrences: 2) }
      let(:generator) { described_class.new(event) }

      before { event.occurrences.destroy_all }

      it 'creates occurrences with cancelled status' do
        generator.generate

        event.occurrences.each do |occ|
          expect(occ.status).to eq('cancelled')
        end
      end
    end
  end

  describe '#regenerate_future!' do
    let(:event) { create(:event, :weekly, max_occurrences: 3) }
    let(:generator) { described_class.new(event) }

    context 'when schedule changes' do
      it 'preserves existing occurrences that are still valid' do
        existing_occ = event.occurrences.first
        original_id = existing_occ.id

        generator.regenerate_future!

        expect(EventOccurrence.find_by(id: original_id)).to be_present
      end

      it 'removes active occurrences that are no longer scheduled' do
        # Create an orphan occurrence that won't be in the schedule
        orphan = event.occurrences.create!(
          occurs_at: 2.years.from_now,
          status: 'active'
        )

        generator.regenerate_future!

        # Should be soft-deleted
        expect(EventOccurrence.find_by(id: orphan.id)).to be_nil
      end

      it 'preserves cancelled occurrences even if not scheduled' do
        orphan = event.occurrences.create!(
          occurs_at: 2.years.from_now,
          status: 'cancelled'
        )

        generator.regenerate_future!

        expect(EventOccurrence.find_by(id: orphan.id)).to be_present
      end

      it 'preserves postponed occurrences even if not scheduled' do
        orphan = event.occurrences.create!(
          occurs_at: 2.years.from_now,
          status: 'postponed'
        )

        generator.regenerate_future!

        expect(EventOccurrence.find_by(id: orphan.id)).to be_present
      end

      it 'does not modify occurs_at for cancelled occurrences on scheduled dates' do
        scheduled_occurrence = event.occurrences.order(:occurs_at).first
        scheduled_occurrence.update!(status: 'cancelled')
        drifted_time = scheduled_occurrence.occurs_at + 1.hour
        scheduled_occurrence.update_column(:occurs_at, drifted_time) # rubocop:disable Rails/SkipsModelValidations

        generator.regenerate_future!

        expect(scheduled_occurrence.reload.occurs_at.utc).to eq(drifted_time.utc)
      end
    end

    context 'with DST correction' do
      let(:event) do
        create(:event, :weekly,
               start_time: la_zone.local(2025, 1, 7, 19, 0, 0),
               max_occurrences: 10)
      end

      it 'maintains consistent wall-clock time across regeneration' do
        generator.regenerate_future!

        # All occurrences should have consistent 7 PM local time
        event.occurrences.reload.each do |occ|
          local_hour = occ.occurs_at.in_time_zone(la_zone).hour
          expect(local_hour).to eq(19), "Expected 7 PM but got #{local_hour}:00"
        end
      end
    end
  end

  describe '#future_scheduled_dates' do
    context 'for a one-time event in the future' do
      let(:event) { create(:event, recurrence_type: 'once', start_time: 1.week.from_now) }
      let(:generator) { described_class.new(event) }

      it 'returns array with the start time' do
        dates = generator.future_scheduled_dates

        expect(dates.length).to eq(1)
        expect(dates.first.to_date).to eq(event.start_time.to_date)
      end
    end

    context 'for a one-time event in the past' do
      let(:event) { create(:event, recurrence_type: 'once', start_time: 1.week.ago) }
      let(:generator) { described_class.new(event) }

      it 'returns empty array' do
        dates = generator.future_scheduled_dates

        expect(dates).to be_empty
      end
    end

    context 'for a recurring event' do
      let(:event) { create(:event, :weekly, max_occurrences: 5) }
      let(:generator) { described_class.new(event) }

      it 'returns up to max_occurrences dates' do
        dates = generator.future_scheduled_dates

        expect(dates.length).to be <= 5
      end

      it 'returns dates with correct timezone' do
        dates = generator.future_scheduled_dates

        dates.each do |date|
          expect(date.time_zone.name).to eq(Time.zone.name)
        end
      end
    end

    context 'for an event without recurrence rule' do
      let(:event) { create(:event, recurrence_type: 'weekly', recurrence_rule: nil) }
      let(:generator) { described_class.new(event) }

      it 'returns empty array' do
        dates = generator.future_scheduled_dates

        expect(dates).to be_empty
      end
    end
  end
end
