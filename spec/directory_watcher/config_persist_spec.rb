require 'spec_helper'

describe DirectoryWatcher do
  scanner_types.each do |scanner|

    context "[#{scanner}]" do

      subject {
        options = default_options.merge(scanner: scanner, persist: scratch_path('persist.yml'))
        watcher = DirectoryWatcher.new(@scratch_dir, options)

        DirectoryWatcherSpecs::Scenario.new(watcher)
      }

      it 'saves the current state of the system when the watcher is stopped' do
        modified_file = scratch_path( 'modified' )
        current_time = Time.now

        subject.run_and_wait_for_event_count(1) do
          touch( modified_file, current_time - 20 )
        end.run_and_wait_for_event_count(1) do
          touch( modified_file, current_time - 10 )
        end.stop

        subject.events.should be_events_like( [[ :added, 'modified'], [ :modified, 'modified' ]] )

        subject.reset
        subject.resume
        Thread.pass until subject.events.size >= 1
        subject.pause

        subject.run_and_wait_for_event_count(1) do
          touch( modified_file )
        end.stop

        subject.events.should be_events_like( [[:added, 'persist.yml'], [ :modified, 'modified' ]] )
      end
    end

  end
end
