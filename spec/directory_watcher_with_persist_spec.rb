require 'spec_helper'

describe DirectoryWatcher do
  context 'refactor' do
    [ nil, :em, :coolio ].each do |scanner|

      let(:default_options) { { :glob => "**/*", :interval => 0.05} }

      subject {
        options = default_options.merge(scanner: scanner, persist: scratch_path('persist.yml'))
        watcher = DirectoryWatcher.new(@scratch_dir, options)

        DirectoryWatcherSpecs::Scenario.new(watcher)
      }

      context "persistence" do
        it "saves the current state of the system when the watcher is stopped" do
          modified_file = scratch_path( 'modified' )
          subject.run_and_wait_for_event_count(1) do
            touch( modified_file, Time.now - 20 )
          end.run_and_wait_for_event_count(1) do
            touch( modified_file, Time.now - 10 )
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
end
