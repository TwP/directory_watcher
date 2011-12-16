shared_examples_for "Scanner" do
  context "Event Types"do
    it "sends added events" do

      scenario.run_and_wait_for_event_count(1) do
        touch( scratch_path( 'added' ) )
      end.stop

      scenario.events.should be_events_like( [[ :added, 'added' ]] )
    end

    it "sends modified events for file size modifications" do

      modified_file = scratch_path( 'modified' )
      scenario.run_and_wait_for_event_count(1) do
        touch( modified_file )
      end.run_and_wait_for_event_count(1) do
        append_to( modified_file )
      end.stop

      scenario.events.should be_events_like( [[ :added, 'modified'], [ :modified, 'modified']] )
    end

    it "sends modified events for mtime modifications" do
      modified_file = scratch_path( 'modified' )

      scenario.run_and_wait_for_event_count(1) do
        touch( modified_file, Time.now - 5 )
      end.run_and_wait_for_event_count(1) do
        touch( modified_file )
      end.stop

      scenario.events.should be_events_like( [[ :added, 'modified'], [ :modified, 'modified']] )
    end

    it "sends removed events" do
      removed_file = scratch_path( 'removed' )
      scenario.run_and_wait_for_event_count(1) do
        touch( removed_file, Time.now )
      end.run_and_wait_for_event_count(1) do
        File.unlink( removed_file )
      end.stop

      scenario.events.should be_events_like [ [:added, 'removed'], [:removed, 'removed'] ]
    end

    it "sends stable events" do
      stable_file = scratch_path( 'stable' )
      scenario_with_stable.run_and_wait_for_event_count(2) do |s|
        touch( stable_file )
        # do nothing wait for the stable event.
      end.stop

      scenario_with_stable.events.should be_events_like [ [:added, 'stable'], [:stable, 'stable'] ]
    end

    it "only sends stable events once" do
      stable_file = scratch_path( 'stable' )
      scenario_with_stable.run_and_wait_for_scan_count(5) do |s|
        touch( stable_file )
        # do nothing
      end.stop

      scenario_with_stable.events.size.should == 2
    end

    it "events are not sent for directory creation" do
      a_dir = scratch_path( 'subdir' )

      scenario.run_and_wait_for_scan_count(2) do
        Dir.mkdir( a_dir )
      end.stop

      scenario.events.should be_empty
    end

    it "sends events for files in sub directories" do
      a_dir = scratch_path( 'subdir' )

      scenario.run_and_wait_for_event_count(1) do
        Dir.mkdir( a_dir )
        subfile = File.join( a_dir, 'subfile' )
        touch( subfile )
      end.stop

      scenario.events.should be_events_like [ [:added, 'subfile'] ]
    end
  end

  context "run_once" do
    it "can be run on command via 'run_once'" do
      one_shot_file = scratch_path( "run_once" )
      scenario.run_once_and_wait_for_event_count(1) do
        touch( one_shot_file )
      end.stop
      scenario.events.should be_events_like [ [:added, 'run_once'] ]
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

  context "running?" do
    it "is true when the watcher is running" do
      directory_watcher.start
      directory_watcher.running?.should be_true
      directory_watcher.stop
    end

    it "is false when the watcher is not running" do
      directory_watcher.running?.should be_false
      directory_watcher.start
      directory_watcher.running?.should be_true
      directory_watcher.stop
      directory_watcher.running?.should be_false
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

  context "sorting" do
    [:ascending, :descending].each do |ordering|
      context "#{ordering}" do
        context "file name" do
          let( :filenames ) { ('a'..'z').sort_by {rand} }
          let( :options   ) { default_options.merge( :order_by => ordering ) }
          before do
            filenames.each do |p|
              touch( scratch_path( p ))
            end
          end

          it "#{ordering}" do
            scenario.run_and_wait_for_event_count(filenames.size) do
              # wait
            end
            final_events = filenames.sort.map { |p| [:added, p] }
            final_events.reverse! if ordering == :descending
            scenario.events.should be_events_like( final_events )
          end
        end

        context "mtime" do
          let( :current_time ) { Time.now }
          let( :basenames    ) { ('a'..'z').to_a }
          let( :delta_times  ) { unique_integer_list( basenames.size, 5000 ) }
          let( :filenames    ) { basenames.inject({}) { |h,k| h[k] = current_time - delta_times.shift; h } }
          let( :options      ) { default_options.merge( :sort_by => :mtime, :order_by => ordering ) }

          before do
            filenames.keys.sort_by{ rand }.each do |p|
              touch( scratch_path(p), filenames[p] )
            end
          end

          it "#{ordering}" do
            scenario.run_and_wait_for_event_count(filenames.size) { nil }
            sorted_fnames = filenames.to_a.sort_by { |v| v[1] }
            final_events = sorted_fnames.map { |fn,ts| [:added, fn] }
            final_events.reverse! if ordering == :descending
            scenario.events.should be_events_like( final_events )
          end
        end

        context "size" do
          let( :basenames  ) { ('a'..'z').to_a }
          let( :file_sizes ) { unique_integer_list( basenames.size, 1000 ) }
          let( :filenames  ) { basenames.inject({}) { |h,k| h[k] = file_sizes.shift; h } }
          let( :options    ) { default_options.merge( :sort_by => :size, :order_by => ordering ) }

          before do
            filenames.keys.sort_by{ rand }.each do |p|
              append_to( scratch_path(p), filenames[p] )
            end
          end

          it "#{ordering}" do
            scenario.run_and_wait_for_event_count(filenames.size) { nil }
            sorted_fnames = filenames.to_a.sort_by { |v| v[1] }
            final_events = sorted_fnames.map { |fn,ts| [:added, fn] }
            final_events.reverse! if ordering == :descending
            scenario.events.should be_events_like( final_events )
          end
        end
      end
    end
  end
end
