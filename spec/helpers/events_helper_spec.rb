# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventsHelper, type: :helper do
  describe '#open_to_badge' do
    it 'labels public events as open to all' do
      html = helper.open_to_badge(build(:event, open_to: 'public'))

      expect(html).to include('Open to All')
      expect(html).to include('bi-door-open')
    end

    it 'labels members events as members only' do
      html = helper.open_to_badge(build(:event, open_to: 'members'))

      expect(html).to include('Members Only')
      expect(html).to include('bi-people-fill')
    end

    it 'labels private events as private' do
      expect(helper.open_to_badge(build(:event, open_to: 'private'))).to include('Private')
    end

    it 'uses the same badge styling for every level' do
      %w[public members private].each do |level|
        expect(helper.open_to_badge(build(:event, open_to: level))).to include('badge bg-secondary')
      end
    end

    it 'adds extra classes' do
      expect(helper.open_to_badge(build(:event), extra_class: 'ms-2')).to include('ms-2')
    end
  end

  describe '#schedule_description' do
    context 'for one-time event' do
      let(:event) { create(:event, recurrence_type: 'once', start_time: Time.zone.parse('2025-06-15 19:00')) }

      it 'returns formatted date' do
        result = helper.schedule_description(event)

        expect(result).to include('June')
        expect(result).to include('15')
        expect(result).to include('2025')
      end
    end

    context 'for weekly event' do
      let(:event) { create(:event, :weekly) }

      it 'returns weekly description' do
        result = helper.schedule_description(event)

        expect(result).to include('Weekly')
      end
    end

    context 'for weekly event with specific days' do
      let(:event) do
        start_time = Time.zone.parse('2025-01-06 19:00') # Monday
        schedule = IceCube::Schedule.new(start_time)
        schedule.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :wednesday))

        create(:event, recurrence_type: 'weekly', start_time: start_time, recurrence_rule: schedule.to_yaml)
      end

      it 'lists the days' do
        result = helper.schedule_description(event)

        expect(result).to include('Monday')
        expect(result).to include('Wednesday')
      end
    end

    context 'for bi-weekly event' do
      let(:event) do
        start_time = Time.zone.parse('2025-01-06 19:00')
        schedule = IceCube::Schedule.new(start_time)
        schedule.add_recurrence_rule(IceCube::Rule.weekly(2).day(:monday))

        create(:event, recurrence_type: 'weekly', start_time: start_time, recurrence_rule: schedule.to_yaml)
      end

      it 'describes the interval' do
        result = helper.schedule_description(event)

        expect(result).to include('Every other week')
      end
    end

    context 'for monthly event on specific week day' do
      let(:event) do
        start_time = Time.zone.parse('2025-01-07 19:00') # First Tuesday
        schedule = IceCube::Schedule.new(start_time)
        schedule.add_recurrence_rule(IceCube::Rule.monthly.day_of_week(tuesday: [1]))

        create(:event, recurrence_type: 'monthly', start_time: start_time, recurrence_rule: schedule.to_yaml)
      end

      it 'describes the occurrence pattern' do
        result = helper.schedule_description(event)

        expect(result).to include('First')
        expect(result).to include('Tuesday')
      end
    end

    context 'for monthly event on day of month' do
      let(:event) do
        start_time = Time.zone.parse('2025-01-15 19:00')
        schedule = IceCube::Schedule.new(start_time)
        schedule.add_recurrence_rule(IceCube::Rule.monthly.day_of_month(15))

        create(:event, recurrence_type: 'monthly', start_time: start_time, recurrence_rule: schedule.to_yaml)
      end

      it 'describes day of month' do
        result = helper.schedule_description(event)

        expect(result).to include('15th')
        expect(result).to include('month')
      end
    end

    context 'for custom schedule' do
      let(:event) { create(:event, recurrence_type: 'custom', recurrence_rule: nil) }

      it 'returns custom schedule label' do
        result = helper.schedule_description(event)

        expect(result).to eq('Custom schedule')
      end
    end
  end

  describe '#parse_weekly_recurrence' do
    context 'with valid weekly rule' do
      let(:event) do
        start_time = Time.zone.parse('2025-01-06 19:00')
        schedule = IceCube::Schedule.new(start_time)
        schedule.add_recurrence_rule(IceCube::Rule.weekly(2).day(:monday, :friday))

        create(:event, recurrence_type: 'weekly', start_time: start_time, recurrence_rule: schedule.to_yaml)
      end

      it 'extracts days' do
        result = helper.parse_weekly_recurrence(event)

        expect(result[:days]).to include(1) # Monday
        expect(result[:days]).to include(5) # Friday
      end

      it 'extracts interval' do
        result = helper.parse_weekly_recurrence(event)

        expect(result[:interval]).to eq(2)
      end
    end

    context 'with non-persisted event' do
      let(:event) { build(:event, :weekly) }

      it 'returns default result' do
        result = helper.parse_weekly_recurrence(event)

        expect(result).to eq({ days: [], interval: 1 })
      end
    end

    context 'with invalid recurrence rule' do
      let(:event) do
        # Create valid event first, then update with invalid rule to skip callback
        e = create(:event, :weekly)
        e.update_column(:recurrence_rule, 'invalid yaml') # rubocop:disable Rails/SkipsModelValidations
        e
      end

      it 'returns default result' do
        result = helper.parse_weekly_recurrence(event)

        expect(result).to eq({ days: [], interval: 1 })
      end
    end
  end

  describe '#parse_monthly_recurrence' do
    context 'with valid monthly rule' do
      let(:event) do
        start_time = Time.zone.parse('2025-01-07 19:00')
        schedule = IceCube::Schedule.new(start_time)
        schedule.add_recurrence_rule(IceCube::Rule.monthly.day_of_week(tuesday: [1, 3]))

        create(:event, recurrence_type: 'monthly', start_time: start_time, recurrence_rule: schedule.to_yaml)
      end

      it 'extracts day name' do
        result = helper.parse_monthly_recurrence(event)

        expect(result[:day]).to eq('tuesday')
      end

      it 'extracts occurrences' do
        result = helper.parse_monthly_recurrence(event)

        expect(result[:occurrences]).to include('first')
        expect(result[:occurrences]).to include('third')
      end
    end

    context 'with exception rules' do
      let(:event) do
        start_time = Time.zone.parse('2025-01-07 19:00')
        schedule = IceCube::Schedule.new(start_time)
        schedule.add_recurrence_rule(IceCube::Rule.monthly.day_of_week(tuesday: [1, 2, 3]))
        schedule.add_exception_rule(IceCube::Rule.monthly.day_of_week(tuesday: [2]))

        create(:event, recurrence_type: 'monthly', start_time: start_time, recurrence_rule: schedule.to_yaml)
      end

      it 'extracts exception occurrences' do
        result = helper.parse_monthly_recurrence(event)

        expect(result[:except_occurrences]).to include('second')
      end
    end
  end

  describe '#interval_description' do
    it 'returns Weekly for interval 1' do
      expect(helper.send(:interval_description, 1)).to eq('Weekly')
    end

    it 'returns Every other week for interval 2' do
      expect(helper.send(:interval_description, 2)).to eq('Every other week')
    end

    it 'returns Every N weeks for larger intervals' do
      expect(helper.send(:interval_description, 3)).to eq('Every 3 weeks')
    end
  end

  describe '#format_list' do
    it 'formats two items' do
      expect(helper.send(:format_list, %w[Monday Tuesday])).to eq('Monday and Tuesday')
    end

    it 'formats three items' do
      expect(helper.send(:format_list, %w[Monday Tuesday Wednesday])).to eq('Monday, Tuesday and Wednesday')
    end
  end
end
