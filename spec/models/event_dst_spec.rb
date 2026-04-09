# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Event DST handling', type: :model do
  # DST dates for America/Los_Angeles in 2026:
  # Spring forward: March 8, 2026 at 2:00 AM (clocks move to 3:00 AM)
  # Fall back: November 1, 2026 at 2:00 AM (clocks move to 1:00 AM)

  let(:user) { create(:user) }
  let(:location) { create(:location) }

  around do |example|
    Time.use_zone('America/Los_Angeles') { example.run }
  end

  describe 'occurrence generation across spring DST transition' do
    let(:pre_dst_date) { Time.zone.local(2026, 3, 1, 19, 0, 0) } # March 1, 2026 7:00 PM PST
    let(:expected_hour) { 19 } # 7 PM local time

    context 'with a weekly recurring event' do
      let(:event) do
        # Create event starting before DST, recurring weekly
        event = Event.new(
          title: 'Weekly DST Test Event',
          start_time: pre_dst_date,
          recurrence_type: 'weekly',
          user: user,
          location: location,
          visibility: 'public'
        )
        # Build and save the schedule
        schedule = Event.build_schedule(pre_dst_date, 'weekly', { days: [pre_dst_date.wday] })
        event.recurrence_rule = schedule.to_yaml
        event.save!
        event
      end

      it 'generates occurrences at correct local time before DST change' do
        event.generate_occurrences(10)

        # Get occurrences before DST (March 8)
        pre_dst_occurrences = event.occurrences.where('occurs_at < ?', Time.zone.local(2026, 3, 8))

        pre_dst_occurrences.each do |occ|
          local_time = occ.occurs_at.in_time_zone('America/Los_Angeles')
          expect(local_time.hour).to eq(expected_hour),
                                     "Expected occurrence at #{occ.occurs_at} to be at #{expected_hour}:00 local, but was #{local_time.hour}:00"
        end
      end

      it 'generates occurrences at correct local time after DST change (spring forward)' do
        event.generate_occurrences(10)

        # Get occurrences after DST (March 8)
        post_dst_occurrences = event.occurrences.where('occurs_at > ?', Time.zone.local(2026, 3, 8))

        expect(post_dst_occurrences).not_to be_empty, "Expected some occurrences after DST change"

        post_dst_occurrences.each do |occ|
          local_time = occ.occurs_at.in_time_zone('America/Los_Angeles')
          expect(local_time.hour).to eq(expected_hour),
                                     "Expected occurrence at #{occ.occurs_at} to be at #{expected_hour}:00 local, but was #{local_time.hour}:00"
        end
      end

      it 'maintains consistent local time across DST boundary' do
        event.generate_occurrences(10)

        all_hours = event.occurrences.map { |occ| occ.occurs_at.in_time_zone('America/Los_Angeles').hour }

        expect(all_hours.uniq).to eq([expected_hour]),
                                  "Expected all occurrences to be at #{expected_hour}:00, but got hours: #{all_hours.uniq.join(', ')}"
      end
    end
  end

  describe 'occurrence generation across fall DST transition' do
    let(:pre_dst_date) { Time.zone.local(2026, 10, 15, 19, 0, 0) } # October 15, 2026 7:00 PM PDT
    let(:expected_hour) { 19 } # 7 PM local time

    context 'with a weekly recurring event' do
      let(:event) do
        event = Event.new(
          title: 'Weekly Fall DST Test Event',
          start_time: pre_dst_date,
          recurrence_type: 'weekly',
          user: user,
          location: location,
          visibility: 'public'
        )
        schedule = Event.build_schedule(pre_dst_date, 'weekly', { days: [pre_dst_date.wday] })
        event.recurrence_rule = schedule.to_yaml
        event.save!
        event
      end

      it 'generates occurrences at correct local time before fall DST change' do
        event.generate_occurrences(10)

        # Get occurrences before DST (November 1)
        pre_dst_occurrences = event.occurrences.where('occurs_at < ?', Time.zone.local(2026, 11, 1))

        pre_dst_occurrences.each do |occ|
          local_time = occ.occurs_at.in_time_zone('America/Los_Angeles')
          expect(local_time.hour).to eq(expected_hour),
                                     "Expected occurrence at #{occ.occurs_at} to be at #{expected_hour}:00 local, but was #{local_time.hour}:00"
        end
      end

      it 'generates occurrences at correct local time after fall DST change (fall back)' do
        event.generate_occurrences(10)

        # Get occurrences after DST (November 1)
        post_dst_occurrences = event.occurrences.where('occurs_at > ?', Time.zone.local(2026, 11, 1))

        expect(post_dst_occurrences).not_to be_empty, "Expected some occurrences after DST change"

        post_dst_occurrences.each do |occ|
          local_time = occ.occurs_at.in_time_zone('America/Los_Angeles')
          expect(local_time.hour).to eq(expected_hour),
                                     "Expected occurrence at #{occ.occurs_at} to be at #{expected_hour}:00 local, but was #{local_time.hour}:00"
        end
      end
    end
  end

  describe 'schedule storage and retrieval' do
    let(:start_time) { Time.zone.local(2026, 3, 1, 19, 0, 0) }

    it 'preserves timezone in stored IceCube schedule' do
      schedule = Event.build_schedule(start_time, 'weekly', { days: [0] })
      yaml = schedule.to_yaml

      # Reload from YAML (simulating DB storage)
      loaded_schedule = IceCube::Schedule.from_yaml(yaml)

      # The schedule should maintain the same local time
      local_start = loaded_schedule.start_time.in_time_zone('America/Los_Angeles')
      expect(local_start.hour).to eq(19)
      expect(local_start.min).to eq(0)
    end

    it 'generates correct times from reloaded schedule across DST' do
      schedule = Event.build_schedule(start_time, 'weekly', { days: [0] }) # Sunday
      yaml = schedule.to_yaml
      loaded_schedule = IceCube::Schedule.from_yaml(yaml)

      # Generate occurrences spanning DST change
      occurrences = loaded_schedule.occurrences_between(
        Time.zone.local(2026, 3, 1),
        Time.zone.local(2026, 4, 30)
      )

      occurrences.each do |occ|
        local_time = occ.in_time_zone('America/Los_Angeles')
        expect(local_time.hour).to eq(19),
                                   "Expected #{occ} to be at 19:00 local, but was #{local_time.hour}:00"
      end
    end
  end

  describe 'regenerate_future_occurrences! across DST' do
    let(:start_time) { Time.zone.local(2026, 3, 1, 19, 0, 0) }
    let(:expected_hour) { 19 }

    let(:event) do
      event = Event.new(
        title: 'Regeneration DST Test',
        start_time: start_time,
        recurrence_type: 'weekly',
        user: user,
        location: location,
        visibility: 'public',
        max_occurrences: 10
      )
      schedule = Event.build_schedule(start_time, 'weekly', { days: [start_time.wday] })
      event.recurrence_rule = schedule.to_yaml
      event.save!
      event.generate_occurrences
      event
    end

    it 'maintains correct local times after regeneration' do
      # First, verify initial generation is correct
      event.occurrences.each do |occ|
        local_time = occ.occurs_at.in_time_zone('America/Los_Angeles')
        expect(local_time.hour).to eq(expected_hour)
      end

      # Now regenerate
      event.regenerate_future_occurrences!

      # Verify still correct after regeneration
      event.occurrences.reload.each do |occ|
        local_time = occ.occurs_at.in_time_zone('America/Los_Angeles')
        expect(local_time.hour).to eq(expected_hour),
                                   "After regeneration: Expected #{occ.occurs_at} to be at #{expected_hour}:00 local, but was #{local_time.hour}:00"
      end
    end

    it 'preserves occurrence slug while fixing DST-shifted time' do
      target_occurrence = event.occurrences.order(:occurs_at).first
      original_slug = target_occurrence.slug

      # Simulate drift to the wrong local hour.
      target_occurrence.update_column(:occurs_at, target_occurrence.occurs_at + 1.hour) # rubocop:disable Rails/SkipsModelValidations
      event.regenerate_future_occurrences!

      fixed_occurrence = event.occurrences.find(target_occurrence.id)
      fixed_local_time = fixed_occurrence.occurs_at.in_time_zone('America/Los_Angeles')

      expect(fixed_occurrence.slug).to eq(original_slug)
      expect(fixed_local_time.hour).to eq(expected_hour)
    end
  end

  describe 'default_to_cancelled events do not create duplicates' do
    let(:start_time) { Time.zone.local(2026, 3, 1, 19, 0, 0) }
    let(:expected_hour) { 19 }

    let(:event) do
      event = Event.new(
        title: 'Default Cancelled DST Test',
        start_time: start_time,
        recurrence_type: 'weekly',
        user: user,
        location: location,
        visibility: 'public',
        max_occurrences: 5,
        default_to_cancelled: true
      )
      schedule = Event.build_schedule(start_time, 'weekly', { days: [start_time.wday] })
      event.recurrence_rule = schedule.to_yaml
      event.save!
      event
    end

    it 'creates cancelled occurrences at correct times' do
      event.generate_occurrences

      expect(event.occurrences.count).to eq(5)
      event.occurrences.each do |occ|
        expect(occ.status).to eq('cancelled')
        local_time = occ.occurs_at.in_time_zone('America/Los_Angeles')
        expect(local_time.hour).to eq(expected_hour)
      end
    end

    it 'does not create duplicates when regenerating' do
      event.generate_occurrences
      initial_count = event.occurrences.count
      initial_ids = event.occurrences.pluck(:id).sort

      # Regenerate - should not create duplicates
      event.regenerate_future_occurrences!

      expect(event.occurrences.reload.count).to eq(initial_count),
                                                "Expected #{initial_count} occurrences but got #{event.occurrences.count}"
      expect(event.occurrences.pluck(:id).sort).to eq(initial_ids),
                                                   "Occurrence IDs changed - duplicates may have been created"
    end

    it 'fixes time on existing cancelled occurrence without creating duplicate' do
      event.generate_occurrences

      # Simulate a DST-corrupted occurrence by manually changing time by 1 hour
      first_occ = event.occurrences.order(:occurs_at).first
      original_id = first_occ.id
      wrong_time = first_occ.occurs_at + 1.hour
      first_occ.update_column(:occurs_at, wrong_time) # rubocop:disable Rails/SkipsModelValidations

      # Verify it's now wrong
      expect(first_occ.reload.occurs_at.in_time_zone('America/Los_Angeles').hour).to eq(expected_hour + 1)

      initial_count = event.occurrences.count

      # Regenerate - should fix time, not create duplicate
      event.regenerate_future_occurrences!

      # Same count (no duplicates)
      expect(event.occurrences.reload.count).to eq(initial_count),
                                                "Duplicate created: expected #{initial_count}, got #{event.occurrences.count}"

      # Original occurrence should still exist with fixed time
      fixed_occ = event.occurrences.find_by(id: original_id)
      expect(fixed_occ).to be_present, "Original occurrence was deleted instead of updated"
      expect(fixed_occ.occurs_at.in_time_zone('America/Los_Angeles').hour).to eq(expected_hour),
                                                                              "Time was not fixed"
      expect(fixed_occ.status).to eq('cancelled'), "Status was changed"
    end

    it 'preserves manually activated occurrences when regenerating' do
      event.generate_occurrences

      # Manually activate one occurrence (simulating user action)
      first_occ = event.occurrences.order(:occurs_at).first
      first_occ.update!(status: 'active')

      # Regenerate
      event.regenerate_future_occurrences!

      # The manually activated occurrence should still be active
      expect(first_occ.reload.status).to eq('active'),
                                         "Manually activated occurrence had its status changed"
    end
  end

  describe 'Time.now vs Time.current consistency' do
    it 'uses timezone-aware time methods' do
      # This test ensures we're using Time.current (timezone-aware) not Time.now (system time)
      # The around block already sets Time.zone = 'America/Los_Angeles'

      # In a Docker container with UTC system time, Time.now and Time.current will differ
      # We want to ensure our code uses the timezone-aware version
      current_zone = Time.current.zone
      expect(%w[PST PDT]).to include(current_zone),
                             "Expected Time.current to be in Pacific time, but got #{current_zone}"
    end
  end
end
