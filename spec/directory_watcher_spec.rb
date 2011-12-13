require 'spec_helper'

describe DirectoryWatcher do

  it "has a version" do
    DirectoryWatcher.version.should =~ /\d\.\d\.\d/
  end

  context 'refactor' do
    [ nil, :em, :coolio ].each do |scanner|

      let( :default_options       ) { { :glob => "**/*", :interval => 0.05}                      }
      let( :options               ) { default_options.merge( :scanner => scanner )               }

      context 'DirectoryWatcher#running?' do

        subject { DirectoryWatcher.new( @scratch_dir, options ) }

        it "is true when the watcher is running" do
          subject.start
          subject.running?.should be_true
          subject.stop
        end

        it "is false when the watcher is not running" do
          subject.running?.should be_false
          subject.start
          subject.running?.should be_true
          subject.stop
          subject.running?.should be_false
        end
      end

      subject {
        directory_watcher = DirectoryWatcher.new( @scratch_dir, options )
        DirectoryWatcherSpecs::Scenario.new( directory_watcher)
      }

      context 'Event Types' do
        it 'sends added events' do
          subject.run_and_wait_for_event_count(1) do
            touch( scratch_path( 'added' ) )
          end.stop

          subject.events.should be_events_like( [[ :added, 'added' ]] )
        end

        it 'sends modified events for file size modifications' do
          modified_file = scratch_path( 'modified' )

          subject.run_and_wait_for_event_count(1) do
            touch( modified_file )
          end.run_and_wait_for_event_count(1) do
            append_to( modified_file )
          end.stop

          subject.events.should be_events_like( [[ :added, 'modified'], [ :modified, 'modified']] )
        end

        it 'sends modified events for mtime modifications' do
          modified_file = scratch_path( 'modified' )

          subject.run_and_wait_for_event_count(1) do
            touch( modified_file, Time.now - 5 )
          end.run_and_wait_for_event_count(1) do
            touch( modified_file )
          end.stop

          subject.events.should be_events_like( [[ :added, 'modified'], [ :modified, 'modified']] )
        end

        it 'sends removed events' do
          removed_file = scratch_path( 'removed' )

          subject.run_and_wait_for_event_count(1) do
            touch( removed_file, Time.now )
          end.run_and_wait_for_event_count(1) do
            File.unlink( removed_file )
          end.stop

          subject.events.should be_events_like( [[:added, 'removed'], [:removed, 'removed']] )
        end

        it 'events are not sent for directory creation' do
          a_dir = scratch_path( 'subdir' )

          subject.run_and_wait_for_scan_count(2) do
            Dir.mkdir( a_dir )
          end.stop

          subject.events.should be_empty
        end

        it 'sends events for files in sub directories' do
          a_dir = scratch_path( 'subdir' )

          subject.run_and_wait_for_event_count(1) do
            Dir.mkdir( a_dir )
            subfile = File.join( a_dir, 'subfile' )
            touch( subfile )
          end.stop

          subject.events.should be_events_like( [[:added, 'subfile']] )
        end
      end

      context "run_once" do
        it "can be run on command via 'run_once'" do
          one_shot_file = scratch_path( "run_once" )

          subject.run_once_and_wait_for_event_count(1) do
            touch( one_shot_file )
          end.stop

          subject.events.should be_events_like( [[:added, 'run_once']] )
        end
      end

      context "sorting" do
        [:ascending, :descending].each do |ordering|
          context "#{ordering}" do

            let( :unique_values ) { unique_sequence }

            context "file name" do
              let( :filenames ) { ('a'..'z').sort_by {rand} }
              let( :options   ) { default_options.merge( :order_by => ordering ) }
              before do
                filenames.each do |p|
                  touch( scratch_path( p ))
                end
              end

              it "#{ordering}" do
                subject.run_and_wait_for_event_count(filenames.size) do
                  # wait
                end
                final_events = filenames.sort.map { |p| [:added, p] }
                final_events.reverse! if ordering == :descending
                subject.events.should be_events_like( final_events )
              end
            end

            context "mtime" do
              let( :current_time ) { Time.now }
              let( :filenames    ) { ('a'..'z').to_a.inject({}) { |h,k| h[k] = current_time - unique_values.next; h } }
              let( :options      ) { default_options.merge( :sort_by => :mtime, :order_by => ordering ) }
              before do
                filenames.keys.sort_by{ rand }.each do |p|
                  touch( scratch_path(p), filenames[p] )
                end
              end

              it "#{ordering}" do
                subject.run_and_wait_for_event_count(filenames.size) { nil }
                sorted_fnames = filenames.to_a.sort_by { |k, v| v }
                final_events = sorted_fnames.map { |fn,ts| [:added, fn] }
                final_events.reverse! if ordering == :descending
                subject.events.should be_events_like( final_events )
              end
            end

            context "size" do
              let( :filenames ) { ('a'..'z').to_a.inject({}) { |h,k| h[k] = unique_values.next; h } }
              let( :options   ) { default_options.merge( :sort_by => :size, :order_by => ordering ) }
              before do
                filenames.keys.sort_by{ rand }.each do |p|
                  append_to( scratch_path(p), filenames[p] )
                end
              end
              it "#{ordering}" do
                subject.run_and_wait_for_event_count(filenames.size) { nil }
                sorted_fnames = filenames.to_a.sort_by { |v| v[1] }
                final_events = sorted_fnames.map { |fn,ts| [:added, fn] }
                final_events.reverse! if ordering == :descending
                subject.events.should be_events_like( final_events )
              end
            end
          end
        end
      end
    end

  end
end

describe "Scanners" do
  [ nil, :em, :coolio ].each do |scanner|
    context "#{scanner} Scanner" do

      let( :default_options       ) { { :glob => "**/*", :interval => 0.05}                      }
      let( :options               ) { default_options.merge( :scanner => scanner )               }
      let( :options_with_glob     ) { options.merge( :glob => '**/*.42' )                        }
      let( :options_with_persist  ) { options.merge( :persist => scratch_path( 'persist.yml' ) ) }

      let( :directory_watcher_with_glob     ) { DirectoryWatcher.new( @scratch_dir, options_with_glob     ) }
      let( :directory_watcher_with_persist  ) { DirectoryWatcher.new( @scratch_dir, options_with_persist  ) }

      let( :scenario_with_glob     ) { DirectoryWatcherSpecs::Scenario.new( directory_watcher_with_glob     ) }
      let( :scenario_with_persist  ) { DirectoryWatcherSpecs::Scenario.new( directory_watcher_with_persist  ) }

      it_should_behave_like 'Scanner'
    end
  end
end

