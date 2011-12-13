require 'spec_helper'

describe DirectoryWatcher do
  [ nil, :em, :coolio ].each do |scanner|

    subject {
      options = default_options.merge(scanner: scanner, stable: 2)
      watcher = DirectoryWatcher.new(@scratch_dir, options)

      DirectoryWatcherSpecs::Scenario.new(watcher)
    }

    it 'sends stable events' do
      stable_file = scratch_path('stable')
      subject.run_and_wait_for_event_count(2) do |s|
        touch( stable_file )
        # do nothing wait for the stable event.
      end.stop

      subject.events.should be_events_like( [[:added, 'stable'], [:stable, 'stable']] )
    end

  end
end
