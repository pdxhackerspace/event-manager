require 'rails_helper'

RSpec.describe 'ordering events by their next occurrence' do
  let(:now) { Time.zone.parse('2026-06-10 12:00') }

  def event_with_occurrences_at(*times, **attrs)
    event = create(:event, **attrs)
    event.occurrences.destroy_all
    times.each { |time| create(:event_occurrence, event: event, occurs_at: time) }
    event
  end

  describe 'EventOccurrence.listable_upcoming' do
    let(:event) { create(:event) }

    before { event.occurrences.destroy_all }

    it 'includes active and relocated occurrences' do
      active = create(:event_occurrence, event: event, occurs_at: 1.day.after(now))
      relocated = create(:event_occurrence, event: event, occurs_at: 2.days.after(now),
                                            status: 'relocated', relocated_to: 'Elsewhere')

      expect(EventOccurrence.listable_upcoming(now)).to contain_exactly(active, relocated)
    end

    it 'excludes cancelled and postponed occurrences' do
      create(:event_occurrence, :cancelled, event: event, occurs_at: 1.day.after(now))
      create(:event_occurrence, :postponed, event: event, occurs_at: 2.days.after(now))

      expect(EventOccurrence.listable_upcoming(now)).to be_empty
    end

    it 'excludes occurrences in the past' do
      create(:event_occurrence, event: event, occurs_at: 1.day.before(now))

      expect(EventOccurrence.listable_upcoming(now)).to be_empty
    end
  end

  describe 'EventOccurrence.next_per_event' do
    it 'returns exactly one row per event, the earliest' do
      first = event_with_occurrences_at(3.days.after(now), 10.days.after(now))
      second = event_with_occurrences_at(1.day.after(now), 20.days.after(now))

      results = EventOccurrence.next_per_event(now).to_a

      expect(results.map(&:event_id)).to contain_exactly(first.id, second.id)
      expect(results.find { |o| o.event_id == first.id }.occurs_at).to be_within(1.second).of(3.days.after(now))
      expect(results.find { |o| o.event_id == second.id }.occurs_at).to be_within(1.second).of(1.day.after(now))
    end

    it 'loads one row per event rather than every future occurrence' do
      3.times { event_with_occurrences_at(*Array.new(6) { |i| (i + 1).weeks.after(now) }) }

      expect(EventOccurrence.next_per_event(now).to_a.size).to eq(3)
    end
  end

  describe 'Event.by_next_occurrence' do
    it 'orders events by whichever occurrence comes next' do
      late = event_with_occurrences_at(30.days.after(now), title: 'Late')
      early = event_with_occurrences_at(1.day.after(now), title: 'Early')
      middle = event_with_occurrences_at(10.days.after(now), title: 'Middle')

      expect(Event.by_next_occurrence(now).to_a).to eq([early, middle, late])
    end

    it 'excludes events with no upcoming listable occurrence' do
      upcoming = event_with_occurrences_at(1.day.after(now))
      past = event_with_occurrences_at(1.day.before(now))
      cancelled_only = create(:event)
      cancelled_only.occurrences.destroy_all
      create(:event_occurrence, :cancelled, event: cancelled_only, occurs_at: 1.day.after(now))

      result = Event.by_next_occurrence(now).to_a

      expect(result).to include(upcoming)
      expect(result).not_to include(past, cancelled_only)
    end

    it 'returns each event once even with many occurrences' do
      event = event_with_occurrences_at(1.day.after(now), 2.days.after(now), 3.days.after(now))

      expect(Event.by_next_occurrence(now).to_a).to eq([event])
    end

    it 'composes with other scopes and conditions' do
      event_with_occurrences_at(1.day.after(now), visibility: 'private', open_to: 'private')
      public_event = event_with_occurrences_at(2.days.after(now), visibility: 'public')

      expect(Event.public_events.by_next_occurrence(now).to_a).to eq([public_event])
    end

    it 'can be counted, as pagination requires' do
      2.times { event_with_occurrences_at(1.day.after(now)) }

      expect(Event.by_next_occurrence(now).count).to eq(2)
    end
  end
end
