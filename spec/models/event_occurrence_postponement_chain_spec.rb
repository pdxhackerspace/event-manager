# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventOccurrence do
  context 'postponement chain' do
    let(:user) { create(:user) }
    let(:event) { create(:event, user: user) }

    def postpone_occurrence(occurrence, until_date)
      occurrence.postpone!(until_date, nil, user)
      occurrence.reload
      occurrence.postponed_to
    end

    describe '#postpone!' do
      let(:occurrence) { create(:event_occurrence, event: event, occurs_at: 1.week.from_now) }
      let(:new_date) { 2.weeks.from_now.change(sec: 0) }

      it 'links the postponed occurrence to the replacement' do
        replacement = postpone_occurrence(occurrence, new_date)
        expect(occurrence.postponed_to).to eq(replacement)
      end

      it 'rolls back when marking postponed fails' do
        replacement = event.occurrences.build(occurs_at: new_date, status: 'active')
        allow(event.occurrences).to receive(:create!).and_return(replacement)
        allow(replacement).to receive(:propagate_rescheduled_time_to_predecessors!)
        allow(occurrence).to receive(:update).and_return(false)
        occurrence.errors.add(:base, 'failed')

        expect do
          expect(occurrence.postpone!(new_date, nil, user)).to be false
        end.not_to(change { event.occurrences.count })

        expect(occurrence.reload.status).to eq('active')
      end
    end

    describe 'propagating rescheduled time' do
      let(:original) { create(:event_occurrence, event: event, occurs_at: 1.week.from_now) }
      let(:first_reschedule) { 2.weeks.from_now.change(sec: 0) }

      it 'updates the original when only the replacement time changes' do
        replacement = postpone_occurrence(original, first_reschedule)
        new_time = first_reschedule + 2.hours
        replacement.current_user_for_journal = user
        replacement.update!(occurs_at: new_time)

        expect(original.reload.postponed_until).to be_within(1.second).of(new_time)
      end

      it 'updates the original when only the replacement date changes' do
        replacement = postpone_occurrence(original, first_reschedule)
        new_time = first_reschedule + 3.days
        replacement.update!(occurs_at: new_time)

        expect(original.reload.postponed_until).to be_within(1.second).of(new_time)
      end

      it 'does not update predecessors when non-schedule fields change' do
        replacement = postpone_occurrence(original, first_reschedule)
        original.update_column(:postponed_until, first_reschedule) # rubocop:disable Rails/SkipsModelValidations
        replacement.update!(custom_description: 'Updated copy')

        expect(original.reload.postponed_until).to be_within(1.second).of(first_reschedule)
      end

      it 'is a no-op when an occurrence has no predecessors' do
        standalone = create(:event_occurrence, event: event, occurs_at: 3.weeks.from_now)
        expect do
          standalone.update!(occurs_at: standalone.occurs_at + 1.hour)
        end.not_to change(EventJournal, :count)
      end

      it 'does not change unrelated postponed occurrences on other events' do
        other_event = create(:event)
        other_postponed = create(:event_occurrence, :postponed, event: other_event)
        replacement = postpone_occurrence(original, first_reschedule)
        replacement.update!(occurs_at: first_reschedule + 4.hours)

        expect(other_postponed.reload.postponed_until).not_to eq(replacement.occurs_at)
      end

      context 'when the replacement is postponed again' do
        let(:second_reschedule) { 3.weeks.from_now.change(sec: 0) }

        it 'updates every predecessor to the latest time' do
          middle = postpone_occurrence(original, first_reschedule)
          final = postpone_occurrence(middle, second_reschedule)

          expect(original.reload.postponed_until).to be_within(1.second).of(second_reschedule)
          expect(middle.reload.postponed_until).to be_within(1.second).of(second_reschedule)
          expect(final.status).to eq('active')
        end

        it 'propagates edits on the final replacement through a three-level chain' do
          middle = postpone_occurrence(original, first_reschedule)
          final = postpone_occurrence(middle, second_reschedule)
          edited = second_reschedule + 90.minutes
          final.update!(occurs_at: edited)

          expect(original.reload.postponed_until).to be_within(1.second).of(edited)
          expect(middle.reload.postponed_until).to be_within(1.second).of(edited)
        end

        it 'does not change the root when a middle postponed record time is edited' do
          middle = postpone_occurrence(original, first_reschedule)
          final = postpone_occurrence(middle, second_reschedule)
          middle.update!(occurs_at: middle.occurs_at + 5.hours)

          expect(original.reload.postponed_until).to be_within(1.second).of(final.occurs_at)
        end
      end
    end

    describe '#rescheduled_time' do
      it 'terminates when a cycle is present' do
        a = create(:event_occurrence, :postponed, event: event, occurs_at: 1.week.from_now,
                                                  postponed_until: 2.weeks.from_now)
        b = create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now, status: 'active')
        a.update_column(:postponed_to_id, b.id) # rubocop:disable Rails/SkipsModelValidations
        b.update_column(:postponed_to_id, a.id) # rubocop:disable Rails/SkipsModelValidations

        expect { a.rescheduled_time }.not_to raise_error
      end
    end

    describe '#replacement_occurrence' do
      it 'returns the linked replacement' do
        original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
        replacement = postpone_occurrence(original, 2.weeks.from_now)
        expect(original.replacement_occurrence).to eq(replacement)
      end

      it 'returns the active tail when the link points at another postponed occurrence' do
        original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
        middle = postpone_occurrence(original, 2.weeks.from_now)
        final = postpone_occurrence(middle, 3.weeks.from_now)

        expect(original.replacement_occurrence).to eq(final)
        expect(middle.replacement_occurrence).to eq(final)
      end

      it 'falls back to occurs_at lookup for legacy records' do
        postponed_until = 2.weeks.from_now.change(sec: 0)
        original = create(:event_occurrence, :postponed, event: event, occurs_at: 1.week.from_now,
                                                         postponed_until: postponed_until)
        replacement = create(:event_occurrence, event: event, occurs_at: postponed_until, status: 'active')
        expect(original.replacement_occurrence).to eq(replacement)
      end

      it 'returns nil when the linked replacement is soft-deleted' do
        event.occurrences.destroy_all
        original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
        replacement = postpone_occurrence(original, 2.weeks.from_now)
        replacement.soft_delete
        original.reload

        expect(original.postponed_to_id).to eq(replacement.id)
        expect(original.replacement_occurrence).to be_nil
      end
    end

    describe 'journal entries' do
      it 'logs predecessor updates when a user is present' do
        original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
        replacement = postpone_occurrence(original, 2.weeks.from_now)
        replacement.current_user_for_journal = user

        expect do
          replacement.update!(occurs_at: replacement.occurs_at + 1.hour)
        end.to change(EventJournal, :count).by(2)

        journal = EventJournal.where(occurrence_id: original.id, action: 'updated').order(:id).last
        expect(journal.change_data).to have_key('postponed_until')
      end

      it 'does not log predecessor updates without a user' do
        original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
        replacement = postpone_occurrence(original, 2.weeks.from_now)

        expect do
          replacement.update!(occurs_at: replacement.occurs_at + 1.hour)
        end.not_to change(EventJournal, :count)
      end
    end

    describe '#reactivate!' do
      it 'clears the postponement link' do
        occurrence = create(:event_occurrence, event: event, occurs_at: 1.week.from_now)
        postpone_occurrence(occurrence, 2.weeks.from_now)
        occurrence.reactivate!(user)
        expect(occurrence.reload.postponed_to_id).to be_nil
      end
    end

    describe 'DST propagation' do
      let(:la_zone) { Time.find_zone('America/Los_Angeles') }

      it 'propagates local wall-clock changes across a DST boundary' do
        original_time = la_zone.local(2025, 3, 1, 19, 0, 0)
        reschedule_time = la_zone.local(2025, 3, 15, 19, 0, 0)
        event.update!(start_time: original_time, recurrence_type: 'once')
        event.occurrences.destroy_all
        original = event.occurrences.create!(occurs_at: original_time)
        replacement = postpone_occurrence(original, reschedule_time)
        edited = la_zone.local(2025, 3, 15, 20, 30, 0)
        replacement.update!(occurs_at: edited)

        expect(original.reload.postponed_until.in_time_zone(la_zone).hour).to eq(20)
        expect(original.postponed_until.in_time_zone(la_zone).min).to eq(30)
      end
    end
  end
end
