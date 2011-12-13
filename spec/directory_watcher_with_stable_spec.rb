require 'spec_helper'

describe DirectoryWatcher do
  context 'refactor' do
    [ nil, :em, :coolio ].each do |scanner|

      let(:default_options) { { :glob => "**/*", :interval => 0.05} }

      subject {
        options = default_options.merge(scanner: scanner, stable: 2)
        watcher = DirectoryWatcher.new(@scratch_dir, options)

        DirectoryWatcherSpecs::Scenario.new(watcher)
      }

      context "Event Types"do
        it "sends stable events" do
          stable_file = scratch_path( 'stable' )
          subject.run_and_wait_for_event_count(2) do |s|
            touch( stable_file )
            # do nothing wait for the stable event.
          end.stop

          subject.events.should be_events_like( [[:added, 'stable'], [:stable, 'stable']] )
        end
      end

    end
  end
end
