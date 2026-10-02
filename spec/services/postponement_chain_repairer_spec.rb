# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostponementChainRepairer do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:event) { create(:event, user: user) }
  let(:io) { StringIO.new }

  def create_postponed_with_journal_replacement(postponed_until, journal_time)
    original = nil
    replacement = nil

    travel_to(journal_time - 1.minute) do
      original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now, status: 'postponed',
                                           postponed_until: postponed_until)
    end
    travel_to(journal_time) do
      EventJournal.log_occurrence_change(original, user, 'postponed', { 'status' => 'postponed' })
    end
    travel_to(journal_time + 30.seconds) do
      replacement = create(:event_occurrence, event: event,
                                              occurs_at: postponed_until + 3.hours, status: 'active')
    end

    [original, replacement]
  end

  def build_legacy_postponed(original_time, postponed_until, replacement_time)
    original = create(:event_occurrence, event: event, occurs_at: original_time, status: 'postponed',
                                         postponed_until: postponed_until)
    replacement = create(:event_occurrence, event: event, occurs_at: replacement_time, status: 'active')
    EventJournal.log_occurrence_change(original, user, 'postponed', { 'status' => 'postponed' })
    [original, replacement]
  end

  describe '#run' do
    it 'links by matching occurs_at' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original, replacement = build_legacy_postponed(1.week.from_now, postponed_until, postponed_until)

      described_class.new(apply: true, io: io).run

      expect(original.reload.postponed_to).to eq(replacement)
    end

    it 'links when the replacement was edited after postponement' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      edited_time = postponed_until + 2.hours
      original, replacement = build_legacy_postponed(1.week.from_now, postponed_until, edited_time)
      EventJournal.log_occurrence_change(
        replacement,
        user,
        'updated',
        { 'occurs_at' => { 'from' => postponed_until, 'to' => edited_time } }
      )

      described_class.new(apply: true, io: io).run

      expect(original.reload.postponed_to).to eq(replacement)
      expect(original.postponed_until).to be_within(1.second).of(edited_time)
    end

    it 'links using slug date and journal window' do
      postponed_until = Time.zone.local(2025, 6, 10, 19, 0, 0)
      journal_time = Time.zone.local(2025, 5, 1, 12, 0, 0)
      original, replacement = create_postponed_with_journal_replacement(postponed_until, journal_time)

      described_class.new(apply: true, io: io).run

      expect(original.reload.postponed_to).to eq(replacement)
    end

    it 'skips ambiguous candidates' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now, status: 'postponed',
                                           postponed_until: postponed_until)
      create(:event_occurrence, event: event, occurs_at: postponed_until, status: 'active')
      create(:event_occurrence, event: event, occurs_at: postponed_until, status: 'active')

      repairer = described_class.new(apply: true, io: io).run

      expect(original.reload.postponed_to_id).to be_nil
      expect(repairer.report[:ambiguous].size).to eq(1)
    end

    it 'does not link across events' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now, status: 'postponed',
                                           postponed_until: postponed_until)
      other_event = create(:event)
      create(:event_occurrence, event: other_event, occurs_at: postponed_until, status: 'active')

      described_class.new(apply: true, io: io).run

      expect(original.reload.postponed_to_id).to be_nil
    end

    it 'does not claim the same replacement twice' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      first = create(:event_occurrence, event: event, occurs_at: 1.week.from_now, status: 'postponed',
                                        postponed_until: postponed_until)
      second = create(:event_occurrence, event: event, occurs_at: 1.week.from_now + 1.day, status: 'postponed',
                                         postponed_until: postponed_until)
      replacement = create(:event_occurrence, event: event, occurs_at: postponed_until, status: 'active')

      described_class.new(apply: true, io: io).run

      linked = [first, second].map { |occ| occ.reload.postponed_to_id }.compact
      expect(linked).to eq([replacement.id])
    end

    it 'is idempotent when applied twice' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original, = build_legacy_postponed(1.week.from_now, postponed_until, postponed_until)

      described_class.new(apply: true, io: io).run
      first_synced = original.reload.postponed_until

      repairer = described_class.new(apply: true, io: io).run
      expect(original.reload.postponed_until).to eq(first_synced)
      expect(repairer.report[:linked]).to be_empty
    end

    it 'does not write in dry run mode' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original, = build_legacy_postponed(1.week.from_now, postponed_until, postponed_until)

      expect do
        described_class.new(apply: false, io: io).run
      end.not_to(change { original.reload.postponed_to_id })
    end

    it 'repairs a multi-level legacy chain' do
      first_date = 2.weeks.from_now.change(sec: 0)
      second_date = 3.weeks.from_now.change(sec: 0)
      edited_final = second_date + 45.minutes
      original, middle = build_legacy_postponed(1.week.from_now, first_date, first_date)
      middle.update!(status: 'postponed', postponed_until: second_date)
      final = create(:event_occurrence, event: event, occurs_at: edited_final, status: 'active')
      journal_data = { 'occurs_at' => { 'from' => second_date, 'to' => edited_final } }
      EventJournal.log_occurrence_change(final, user, 'updated', journal_data)

      described_class.new(apply: true, io: io).run

      expect(original.reload.postponed_to).to eq(middle)
      expect(middle.reload.postponed_to).to eq(final)
      expect(original.postponed_until).to be_within(1.second).of(edited_final)
      expect(middle.postponed_until).to be_within(1.second).of(edited_final)
    end
  end

  describe '#link_manual!' do
    it 'links and syncs when apply is true' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      edited = postponed_until + 1.hour
      original, replacement = build_legacy_postponed(1.week.from_now, postponed_until, edited)

      described_class.new(apply: true, io: io).link_manual!(original, replacement)

      expect(original.reload.postponed_to).to eq(replacement)
      expect(original.postponed_until).to be_within(1.second).of(edited)
    end
  end
end
