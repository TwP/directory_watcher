require 'spec_helper'

describe DirectoryWatcher do
  scanner_types.each do |scanner|

    context "[#{scanner}]" do

      subject {
        options = default_options.merge(scanner: scanner, glob: '**/*.rb', ignore_glob: '**/ignored.rb')
        watcher = DirectoryWatcher.new(@scratch_dir, options)

        DirectoryWatcherSpecs::Scenario.new(watcher)
      }

      it 'should ignore files which are specified in ignore glob' do
        pending

        matching = scratch_path( 'matched.rb' )
        ignored = scratch_path( 'ignored.rb' )

        subject.run_and_wait_for_event_count(1) do
          touch( ignored )
          touch( matching, Time.now - 5 )
        end.run_and_wait_for_event_count(1) do
          touch( matching )
        end.stop

        subject.events.should be_events_like( [[ :added, 'matched.rb' ], [ :modified, 'matched.rb' ]] )
      end
    end

  end
end
