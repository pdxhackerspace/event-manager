require 'rails_helper'

RSpec.describe EventOccurrence, type: :model do
  describe 'validations' do
    subject { build(:event_occurrence) }

    it { is_expected.to validate_presence_of(:occurs_at) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active postponed cancelled]) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:event) }
    it { is_expected.to have_one_attached(:banner_image) }
  end

  describe 'scopes' do
    let(:event) { create(:event) }
    let!(:active_occ) { create(:event_occurrence, event: event, status: 'active') }
    let!(:postponed_occ) { create(:event_occurrence, :postponed, event: event) }
    let!(:cancelled_occ) { create(:event_occurrence, :cancelled, event: event) }
    let!(:future_occ) { create(:event_occurrence, event: event, occurs_at: 1.week.from_now) }
    let!(:past_occ) { create(:event_occurrence, :past, event: event) }

    describe '.active' do
      it 'returns only active occurrences' do
        expect(described_class.active).to include(active_occ, future_occ)
        expect(described_class.active).not_to include(postponed_occ, cancelled_occ)
      end
    end

    describe '.postponed' do
      it 'returns only postponed occurrences' do
        expect(described_class.postponed).to include(postponed_occ)
        expect(described_class.postponed).not_to include(active_occ, cancelled_occ)
      end
    end

    describe '.cancelled' do
      it 'returns only cancelled occurrences' do
        expect(described_class.cancelled).to include(cancelled_occ)
        expect(described_class.cancelled).not_to include(active_occ, postponed_occ)
      end
    end

    describe '.upcoming' do
      it 'returns only future occurrences' do
        expect(described_class.upcoming).to include(future_occ)
        expect(described_class.upcoming).not_to include(past_occ)
      end

      it 'orders by occurs_at ascending' do
        create(:event_occurrence, event: event, occurs_at: 2.weeks.from_now)
        upcoming = described_class.upcoming
        expect(upcoming.first.occurs_at).to be < upcoming.last.occurs_at
      end
    end

    describe '.past' do
      it 'returns only past occurrences' do
        expect(described_class.past).to include(past_occ)
        expect(described_class.past).not_to include(future_occ)
      end

      it 'orders by occurs_at descending' do
        create(:event_occurrence, event: event, occurs_at: 2.weeks.ago)
        past = described_class.past
        expect(past.first.occurs_at).to be > past.last.occurs_at
      end
    end
  end

  describe '#description' do
    let(:event) { create(:event, description: 'Event description') }

    context 'when occurrence has custom description' do
      let(:occurrence) { create(:event_occurrence, :with_custom_description, event: event) }

      it 'returns the custom description' do
        expect(occurrence.description).to eq(occurrence.custom_description)
      end
    end

    context 'when occurrence has no custom description' do
      let(:occurrence) { create(:event_occurrence, event: event) }

      it 'returns the event description' do
        expect(occurrence.description).to eq(event.description)
      end
    end

    context 'when custom description is blank' do
      let(:occurrence) { create(:event_occurrence, event: event, custom_description: '') }

      it 'returns the event description' do
        expect(occurrence.description).to eq(event.description)
      end
    end
  end

  describe '#duration' do
    let(:event) { create(:event, duration: 120) }

    context 'when occurrence has duration override' do
      let(:occurrence) { create(:event_occurrence, :with_duration_override, event: event) }

      it 'returns the override duration' do
        expect(occurrence.duration).to eq(occurrence.duration_override)
      end
    end

    context 'when occurrence has no duration override' do
      let(:occurrence) { create(:event_occurrence, event: event) }

      it 'returns the event duration' do
        expect(occurrence.duration).to eq(event.duration)
      end
    end
  end

  describe '#banner' do
    let(:event) { create(:event) }

    context 'when occurrence has its own banner' do
      let(:occurrence) { create(:event_occurrence, :with_banner, event: event) }

      it 'returns the occurrence banner' do
        expect(occurrence.banner).to eq(occurrence.banner_image)
      end
    end

    context 'when occurrence has no banner but event does' do
      let(:event_with_banner) { create(:event, :with_banner) }
      let(:occurrence) { create(:event_occurrence, event: event_with_banner) }

      it 'returns the event banner' do
        expect(occurrence.banner).to eq(event_with_banner.banner_image)
      end
    end

    context 'when neither occurrence nor event has banner' do
      let(:occurrence) { create(:event_occurrence, event: event) }

      it 'returns the event banner_image (not attached)' do
        expect(occurrence.banner).to eq(event.banner_image)
        expect(occurrence.banner.attached?).to be false
      end
    end
  end

  describe '#postpone!' do
    let(:user) { create(:user) }
    let(:occurrence) { create(:event_occurrence) }
    let(:new_date) { 2.weeks.from_now }

    it 'changes status to postponed' do
      occurrence.postpone!(new_date, nil, user)
      expect(occurrence.status).to eq('postponed')
    end

    it 'sets postponed_until date' do
      occurrence.postpone!(new_date, nil, user)
      expect(occurrence.postponed_until).to be_within(1.second).of(new_date)
    end

    it 'sets cancellation_reason when provided' do
      occurrence.postpone!(new_date, 'Speaker unavailable', user)
      expect(occurrence.cancellation_reason).to eq('Speaker unavailable')
    end

    it 'returns true on success' do
      result = occurrence.postpone!(new_date, nil, user)
      expect(result).to be true
    end
  end

  describe '#cancel!' do
    let(:user) { create(:user) }
    let(:occurrence) { create(:event_occurrence) }

    it 'changes status to cancelled' do
      occurrence.cancel!(nil, user)
      expect(occurrence.status).to eq('cancelled')
    end

    it 'sets cancellation_reason when provided' do
      occurrence.cancel!('Weather conditions', user)
      expect(occurrence.cancellation_reason).to eq('Weather conditions')
    end

    it 'returns true on success' do
      result = occurrence.cancel!(nil, user)
      expect(result).to be true
    end
  end

  describe '#reactivate!' do
    let(:user) { create(:user) }
    let(:occurrence) { create(:event_occurrence, :cancelled) }

    it 'changes status to active' do
      occurrence.reactivate!(user)
      expect(occurrence.status).to eq('active')
    end

    it 'clears postponed_until' do
      postponed_occ = create(:event_occurrence, :postponed)
      postponed_occ.reactivate!(user)
      expect(postponed_occ.postponed_until).to be_nil
    end

    it 'clears cancellation_reason' do
      postponed_occ = create(:event_occurrence, :postponed)
      postponed_occ.reactivate!(user)
      expect(postponed_occ.cancellation_reason).to be_nil
    end

    it 'returns true on success' do
      result = occurrence.reactivate!(user)
      expect(result).to be true
    end
  end

  describe '#name' do
    let(:event) { create(:event, title: 'Weekly Meetup') }
    let(:occurrence) { create(:event_occurrence, event: event, occurs_at: Time.zone.parse('2025-11-15 19:00')) }

    it 'returns event title with date' do
      expect(occurrence.name).to eq('Weekly Meetup - November 15, 2025')
    end
  end

  describe 'slug stability' do
    it 'does not change slug when occurs_at changes on an existing occurrence' do
      event = create(:event, :weekly)
      occurrence = event.occurrences.order(:id).first
      original_slug = occurrence.slug

      occurrence.update!(occurs_at: occurrence.occurs_at + 1.hour)

      expect(occurrence.reload.slug).to eq(original_slug)
    end
  end

  describe 'factory' do
    it 'creates a valid occurrence' do
      occurrence = build(:event_occurrence)
      expect(occurrence).to be_valid
    end

    it 'creates a valid occurrence with custom description' do
      occurrence = build(:event_occurrence, :with_custom_description)
      expect(occurrence).to be_valid
      expect(occurrence.custom_description).to be_present
    end

    it 'creates a valid occurrence with duration override' do
      occurrence = build(:event_occurrence, :with_duration_override)
      expect(occurrence).to be_valid
      expect(occurrence.duration_override).to eq(180)
    end

    it 'creates a valid postponed occurrence' do
      occurrence = build(:event_occurrence, :postponed)
      expect(occurrence).to be_valid
      expect(occurrence.status).to eq('postponed')
      expect(occurrence.postponed_until).to be_present
    end

    it 'creates a valid cancelled occurrence' do
      occurrence = build(:event_occurrence, :cancelled)
      expect(occurrence).to be_valid
      expect(occurrence.status).to eq('cancelled')
    end
  end
end
