require 'spec_helper'

describe DirectoryWatcher do
  scanner_types.each do |scanner|

    context "[#{scanner}]" do

      let(:scenario_single) {
        options = default_options.merge(scanner: scanner, ignore_glob: 'ignored.rb')
        watcher = DirectoryWatcher.new(@scratch_dir, options)

        DirectoryWatcherSpecs::Scenario.new(watcher)
      }

      let(:scenario_multiple) {
        options = default_options.merge(scanner: scanner, ignore_glob: %w(*.rb *.py))
        watcher = DirectoryWatcher.new(@scratch_dir, options)

        DirectoryWatcherSpecs::Scenario.new(watcher)
      }

      it 'should ignore files which are specified in ignore glob' do
        matching = scratch_path( 'matched.rb' )
        ignored = scratch_path( 'ignored.rb' )

        scenario_single.run_and_wait_for_event_count(1) do
          touch( ignored )
          touch( matching, Time.now - 5 )
        end.run_and_wait_for_event_count(1) do
          touch( matching )
        end.stop

        scenario_single.events.should be_events_like( [[ :added, 'matched.rb' ], [ :modified, 'matched.rb' ]] )
      end

      it 'should ignore files which are specified in ignore glob' do
        files = %w(matched1.txt matched2.csv ignored.py ignored.rb)

        scenario_multiple.run_and_wait_for_event_count(2) do
          files.each { |f| touch( scratch_path( f ) ) }
        end.stop

        scenario_multiple.events.should be_events_like( [[ :added, 'matched1.txt' ], [ :added, 'matched2.csv' ]] )
      end
    end

  end
end
