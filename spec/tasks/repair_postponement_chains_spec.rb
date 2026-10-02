# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'events postponement chain rake tasks' do
  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['events:repair_postponement_chains'].reenable
    Rake::Task['events:link_postponement'].reenable
  end

  after do
    ENV.delete('APPLY')
  end

  let(:user) { create(:user) }
  let(:event) { create(:event, user: user) }

  describe 'events:repair_postponement_chains' do
    it 'runs as a dry run by default' do
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now, status: 'postponed',
                                           postponed_until: postponed_until)
      create(:event_occurrence, event: event, occurs_at: postponed_until, status: 'active')

      expect do
        Rake::Task['events:repair_postponement_chains'].invoke
      end.not_to(change { original.reload.postponed_to_id })
    end

    it 'applies changes when APPLY=1' do
      ENV['APPLY'] = '1'
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now, status: 'postponed',
                                           postponed_until: postponed_until)
      replacement = create(:event_occurrence, event: event, occurs_at: postponed_until, status: 'active')

      Rake::Task['events:repair_postponement_chains'].invoke

      expect(original.reload.postponed_to).to eq(replacement)
    end
  end

  describe 'events:link_postponement' do
    it 'links a specific pair when APPLY=1' do
      ENV['APPLY'] = '1'
      postponed_until = 2.weeks.from_now.change(sec: 0)
      original = create(:event_occurrence, event: event, occurs_at: 1.week.from_now, status: 'postponed',
                                           postponed_until: postponed_until)
      replacement = create(:event_occurrence, event: event, occurs_at: postponed_until + 2.hours, status: 'active')

      Rake::Task['events:link_postponement'].invoke(original.slug, replacement.slug)

      expect(original.reload.postponed_to).to eq(replacement)
    end
  end
end
