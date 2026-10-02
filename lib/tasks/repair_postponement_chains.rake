namespace :events do
  desc 'Repair postponement chains (dry run unless APPLY=1)'
  task repair_postponement_chains: :environment do
    apply = ENV['APPLY'] == '1'
    puts apply ? 'Applying postponement chain repairs...' : 'Dry run (no changes). Set APPLY=1 to write.'
    puts ''

    repairer = PostponementChainRepairer.new(apply: apply)
    repairer.run

    puts ''
    puts "Linked: #{repairer.report[:linked].size}, synced: #{repairer.report[:synced].size}, " \
         "ambiguous: #{repairer.report[:ambiguous].size}, skipped: #{repairer.report[:skipped].size}"
    puts 'Done!'
  end

  desc 'Manually link a postponed occurrence to its replacement (dry run unless APPLY=1)'
  task :link_postponement, %i[postponed replacement] => :environment do |_task, args|
    apply = ENV['APPLY'] == '1'
    postponed = EventOccurrence.friendly_find(args[:postponed])
    replacement = EventOccurrence.friendly_find(args[:replacement])

    raise "Postponed occurrence not found: #{args[:postponed]}" unless postponed
    raise "Replacement occurrence not found: #{args[:replacement]}" unless replacement

    puts apply ? 'Applying manual link...' : 'Dry run (no changes). Set APPLY=1 to write.'
    PostponementChainRepairer.new(apply: apply).link_manual!(postponed, replacement)
    puts 'Done!'
  end
end
