require 'rails_helper'

RSpec.describe RecurrenceParams do
  def params_for(hash)
    ActionController::Parameters.new(hash)
  end

  describe '#to_h' do
    context 'for a weekly event' do
      it 'maps the submitted days and interval' do
        params = params_for(event: { recurrence_type: 'weekly' },
                            recurrence_days: %w[1 3],
                            recurrence_interval: '2')

        expect(described_class.new(params).to_h).to eq(days: [1, 3], interval: 2)
      end

      it "falls back to the start time's weekday when no days are given" do
        start_time = Time.zone.parse('2026-06-10 18:00') # a Wednesday
        params = params_for(event: { recurrence_type: 'weekly', start_time: start_time.to_s })

        expect(described_class.new(params).to_h).to eq(days: [3], interval: 1)
      end

      it 'clamps a non-positive interval to 1' do
        params = params_for(event: { recurrence_type: 'weekly' },
                            recurrence_days: %w[1],
                            recurrence_interval: '0')

        expect(described_class.new(params).to_h[:interval]).to eq(1)
      end
    end

    context 'for a monthly event' do
      it 'maps occurrences, exceptions and day' do
        params = params_for(event: { recurrence_type: 'monthly' },
                            recurrence_occurrences: %w[first third],
                            recurrence_except_occurrences: %w[last],
                            recurrence_day: 'tuesday')

        expect(described_class.new(params).to_h).to eq(
          occurrences: %w[first third],
          except_occurrences: %w[last],
          day: 'tuesday'
        )
      end

      it 'drops a day that is not a real weekday name' do
        params = params_for(event: { recurrence_type: 'monthly' },
                            recurrence_occurrences: %w[first],
                            recurrence_day: 'not_a_day')

        expect(described_class.new(params).to_h).to eq(occurrences: %w[first])
      end
    end

    context 'for a custom event' do
      # The form submits custom_rules[0][...], which Rails parses as a hash
      # keyed by index rather than an array.
      it 'reads rules from the index-keyed hash the form submits' do
        params = params_for(
          event: { recurrence_type: 'custom' },
          custom_rules: {
            '0' => { type: 'weekly', days: %w[2], interval: '2', week_offset: '1' },
            '1' => { type: 'monthly', occurrences: %w[first], day: 'thursday' }
          }
        )

        expect(described_class.new(params).to_h[:custom_rules]).to eq(
          [
            { type: 'weekly', days: [2], interval: 2, week_offset: 1 },
            { type: 'monthly', occurrences: %w[first], day: 'thursday' }
          ]
        )
      end

      it 'also accepts an array of rules' do
        params = params_for(
          event: { recurrence_type: 'custom' },
          custom_rules: [{ type: 'weekly', days: %w[5], interval: '1' }]
        )

        expect(described_class.new(params).to_h[:custom_rules]).to eq(
          [{ type: 'weekly', days: [5], interval: 1, week_offset: 0 }]
        )
      end

      it 'ignores rules with an unrecognized type' do
        params = params_for(event: { recurrence_type: 'custom' },
                            custom_rules: { '0' => { type: 'yearly' } })

        expect(described_class.new(params).to_h[:custom_rules]).to eq([])
      end

      it 'produces rules Event.build_schedule accepts' do
        start_time = Time.zone.parse('2026-06-10 18:00')
        params = params_for(
          event: { recurrence_type: 'custom' },
          custom_rules: { '0' => { type: 'weekly', days: %w[3], interval: '1' } }
        )
        options = described_class.new(params).to_h

        schedule = Event.build_schedule(start_time, 'custom', options)

        expect(schedule.occurrences_between(start_time, 4.weeks.after(start_time)).size).to be > 1
      end
    end

    it 'returns an empty hash for a one-off event' do
      params = params_for(event: { recurrence_type: 'once' })

      expect(described_class.new(params).to_h).to eq({})
    end
  end

  describe '#start_time' do
    let(:event) { build(:event, start_time: Time.zone.parse('2026-01-01 10:00')) }

    it 'prefers the submitted start time' do
      params = params_for(event: { recurrence_type: 'weekly', start_time: '2026-06-10 18:00' })

      expect(described_class.new(params, event: event).start_time).to eq(Time.zone.parse('2026-06-10 18:00'))
    end

    it "falls back to the event's start time" do
      params = params_for(event: { recurrence_type: 'weekly' })

      expect(described_class.new(params, event: event).start_time).to eq(event.start_time)
    end
  end

  describe '#rebuild_schedule?' do
    let(:event) do
      create(:event, :weekly, start_time: Time.zone.parse('2026-06-10 18:00'), recurrence_type: 'weekly')
    end

    it 'is false when no recurrence type was submitted' do
      params = params_for(event: { title: 'Renamed' })

      expect(described_class.new(params, event: event).rebuild_schedule?).to be false
    end

    it 'is false when nothing recurrence-related changed' do
      params = params_for(event: { recurrence_type: 'weekly', start_time: event.start_time.to_s })

      expect(described_class.new(params, event: event).rebuild_schedule?).to be false
    end

    it 'is true when the recurrence type changed' do
      params = params_for(event: { recurrence_type: 'monthly' })

      expect(described_class.new(params, event: event).rebuild_schedule?).to be true
    end

    it 'is true when the start time changed' do
      params = params_for(event: { recurrence_type: 'weekly', start_time: '2026-07-01 19:00' })

      expect(described_class.new(params, event: event).rebuild_schedule?).to be true
    end

    it 'is true when weekly options were submitted' do
      params = params_for(event: { recurrence_type: 'weekly' }, recurrence_days: %w[1])

      expect(described_class.new(params, event: event).rebuild_schedule?).to be true
    end

    it 'is true when monthly exception options were submitted' do
      params = params_for(event: { recurrence_type: 'weekly' }, recurrence_except_occurrences: %w[last])

      expect(described_class.new(params, event: event).rebuild_schedule?).to be true
    end

    it 'is true when custom rules were submitted' do
      params = params_for(event: { recurrence_type: 'weekly' },
                          custom_rules: { '0' => { type: 'weekly', days: %w[1] } })

      expect(described_class.new(params, event: event).rebuild_schedule?).to be true
    end
  end
end
