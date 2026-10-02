# frozen_string_literal: true

# Links legacy postponed occurrences to their replacements and syncs postponed_until
# through postponement chains.
class PostponementChainRepairer
  JOURNAL_WINDOW = 2.minutes

  attr_reader :report

  def initialize(apply: false, io: $stdout)
    @apply = apply
    @io = io
    @report = { linked: [], synced: [], ambiguous: [], skipped: [], errors: [] }
  end

  def run
    link_unlinked_postponements
    sync_postponed_until_values
    self
  end

  def link_manual!(postponed, replacement)
    validate_manual_link!(postponed, replacement)

    evidence = 'manual'
    if @apply
      postponed.update!(postponed_to: replacement)
      sync_occurrence(postponed, evidence: evidence)
    else
      log_link(postponed, replacement, evidence, dry_run: true)
    end
    self
  end

  private

  def link_unlinked_postponements
    claimed_replacement_ids = EventOccurrence.where.not(postponed_to_id: nil).pluck(:postponed_to_id).to_set

    EventOccurrence.postponed.where.not(postponed_until: nil).where(postponed_to_id: nil).find_each do |postponed|
      candidates = matching_replacements(postponed, claimed_replacement_ids)
      if candidates.one?
        candidate = candidates.first
        evidence = match_evidence(postponed, candidate)
        if @apply
          postponed.update!(postponed_to: candidate)
          claimed_replacement_ids.add(candidate.id)
          @report[:linked] << { postponed_id: postponed.id, replacement_id: candidate.id, evidence: evidence }
          log_link(postponed, candidate, evidence, dry_run: false)
        else
          log_link(postponed, candidate, evidence, dry_run: true)
        end
      elsif candidates.empty?
        message = "No replacement candidate for postponed occurrence ##{postponed.id} (#{postponed.slug})"
        @report[:skipped] << message
        @io.puts message
      else
        message = "Ambiguous replacement for postponed occurrence ##{postponed.id} (#{postponed.slug}): " \
                  "candidates #{candidates.map(&:id).join(', ')}"
        @report[:ambiguous] << message
        @io.puts message
      end
    end
  end

  def sync_postponed_until_values
    EventOccurrence.postponed.where.not(postponed_to_id: nil).find_each do |postponed|
      sync_occurrence(postponed)
    end
  end

  def sync_occurrence(postponed, evidence: nil)
    latest = postponed.rescheduled_time
    return if times_equal?(postponed.postponed_until, latest)

    old_value = postponed.postponed_until
    if @apply
      postponed.update!(postponed_until: latest)
      @report[:synced] << {
        occurrence_id: postponed.id,
        from: old_value,
        to: latest,
        evidence: evidence
      }
      @io.puts "  Synced ##{postponed.id}: #{old_value} -> #{latest}"
    else
      @io.puts "  Would sync ##{postponed.id}: #{old_value} -> #{latest}"
    end
  end

  def matching_replacements(postponed, claimed_replacement_ids)
    postponed.event.occurrences
             .where.not(id: postponed.id)
             .where(created_at: postponed.created_at..)
             .order(:id)
             .select do |candidate|
      next false if claimed_replacement_ids.include?(candidate.id)

      matches_replacement?(postponed, candidate)
    end
  end

  def matches_replacement?(postponed, candidate)
    occurs_at_matches?(postponed, candidate) ||
      journal_edit_from_postponed_until?(postponed, candidate) ||
      slug_and_journal_window_match?(postponed, candidate)
  end

  def match_evidence(postponed, candidate)
    return 'occurs_at' if occurs_at_matches?(postponed, candidate)
    return 'journal_occurs_at' if journal_edit_from_postponed_until?(postponed, candidate)

    'slug_and_journal_window'
  end

  def occurs_at_matches?(postponed, candidate)
    times_equal?(candidate.occurs_at, postponed.postponed_until)
  end

  def journal_edit_from_postponed_until?(postponed, candidate)
    EventJournal.where(occurrence_id: candidate.id, action: 'updated').find_each do |entry|
      from_time = entry.change_data.dig('occurs_at', 'from')
      next if from_time.blank?

      return true if times_equal?(Time.zone.parse(from_time.to_s), postponed.postponed_until)
    end
    false
  end

  def slug_and_journal_window_match?(postponed, candidate)
    postponed_journal = EventJournal.where(occurrence_id: postponed.id, action: 'postponed')
                                    .order(:created_at)
                                    .first
    return false unless postponed_journal

    slug_date = candidate.slug&.match(/(\d{4}-\d{2}-\d{2})/)&.[](1)
    return false if slug_date.blank?

    target_date = postponed.postponed_until.in_time_zone(Time.zone).strftime('%Y-%m-%d')
    return false unless slug_date == target_date

    (candidate.created_at - postponed_journal.created_at).abs <= JOURNAL_WINDOW
  end

  def log_link(postponed, replacement, evidence, dry_run:)
    prefix = dry_run ? 'Would link' : 'Linked'
    @io.puts "#{prefix} postponed ##{postponed.id} -> replacement ##{replacement.id} (#{evidence})"
  end

  def validate_manual_link!(postponed, replacement)
    raise ArgumentError, 'Postponed occurrence must have status postponed' unless postponed.status == 'postponed'
    raise ArgumentError, 'Replacement must belong to the same event' unless postponed.event_id == replacement.event_id
    raise ArgumentError, 'Cannot link occurrence to itself' if postponed.id == replacement.id
  end

  def times_equal?(left, right)
    return true if left.blank? && right.blank?
    return false if left.blank? || right.blank?

    left.to_i == right.to_i
  end
end
