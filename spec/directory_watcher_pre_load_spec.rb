require 'spec_helper'

describe DirectoryWatcher do
  context 'refactor' do
    [ nil, :em, :coolio ].each do |scanner|

      let(:default_options) { { :glob => "**/*", :interval => 0.05} }
      let(:options) { default_options.merge(scanner: scanner, pre_load: true) }

      subject {
        watcher = DirectoryWatcher.new(@scratch_dir, options)
        DirectoryWatcherSpecs::Scenario.new(watcher)
      }

      context 'pre_load option' do
        it 'skips initial add events' do
          modified_file = scratch_path( 'modified' )
          touch( modified_file, Time.now - 5 )

          subject.run_and_wait_for_event_count(1) do
            touch( modified_file )
          end.stop

          subject.events.should be_events_like( [[ :modified, 'modified']] )
        end
      end
    end
  end
end
