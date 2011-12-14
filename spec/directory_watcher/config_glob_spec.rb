require 'spec_helper'

describe DirectoryWatcher do
  scanner_types.each do |scanner|

    subject {
      options = default_options.merge(scanner: scanner, glob: '**/*.42')
      watcher = DirectoryWatcher.new(@scratch_dir, options)

      DirectoryWatcherSpecs::Scenario.new(watcher)
    }

    it 'only sends events for files that match' do
      non_matching = scratch_path( 'no-match' )
      matching = scratch_path( 'match.42' )

      subject.run_and_wait_for_event_count(1) do
        touch( non_matching )
        touch( matching, Time.now - 5 )
      end.run_and_wait_for_event_count(1) do
        touch( matching )
      end.stop

      subject.events.should be_events_like( [[ :added, 'match.42' ], [ :modified, 'match.42' ]] )
    end

  end
end
