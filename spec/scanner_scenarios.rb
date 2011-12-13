shared_examples_for "Scanner" do

  context "Event Types"do
    it "sends stable events" do
      stable_file = scratch_path( 'stable' )
      scenario_with_stable.run_and_wait_for_event_count(2) do |s|
        touch( stable_file )
        # do nothing wait for the stable event.
      end.stop

      scenario_with_stable.events.should be_events_like( [[:added, 'stable'], [:stable, 'stable']] )
    end
  end

  context "pre_load option " do
    it "skips initial add events" do
      modified_file = scratch_path( 'modified' )
      touch( modified_file, Time.now - 5 )

      scenario_with_pre_load.run_and_wait_for_event_count(1) do
        touch( modified_file )
      end.stop

      scenario_with_pre_load.events.should be_events_like( [[ :modified, 'modified']] )
    end
  end

  context "globbing" do
    it "only sends events for files that match" do
      non_matching = scratch_path( 'no-match' )
      matching = scratch_path( 'match.42' )

      scenario_with_glob.run_and_wait_for_event_count(1) do
        touch( non_matching )
        touch( matching, Time.now - 5 )
      end.run_and_wait_for_event_count(1) do
        touch( matching )
      end.stop

      scenario_with_glob.events.should be_events_like( [[ :added, 'match.42' ], [ :modified, 'match.42' ]] )
    end
  end

  context "persistence" do
    it "saves the current state of the system when the watcher is stopped" do
      modified_file = scratch_path( 'modified' )
      scenario_with_persist.run_and_wait_for_event_count(1) do
        touch( modified_file, Time.now - 20 )
      end.run_and_wait_for_event_count(1) do
        touch( modified_file, Time.now - 10 )
      end.stop

      scenario_with_persist.events.should be_events_like( [[ :added, 'modified'], [ :modified, 'modified' ]] )

      scenario_with_persist.reset
      scenario_with_persist.resume
      Thread.pass until scenario_with_persist.events.size >= 1
      scenario_with_persist.pause

      scenario_with_persist.run_and_wait_for_event_count(1) do
        touch( modified_file )
      end.stop

      scenario_with_persist.events.should be_events_like( [[:added, 'persist.yml'], [ :modified, 'modified' ]] )
    end
  end

end
