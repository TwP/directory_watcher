require 'spec_helper'

describe DirectoryWatcher do

  it 'has a version' do
    DirectoryWatcher.version.should =~ /\d\.\d\.\d/
  end

  scanner_types.each do |scanner|

    let(:options) { default_options.merge(scanner: scanner) }

    context 'DirectoryWatcher#running?' do

      subject { DirectoryWatcher.new(@scratch_dir, options) }

      it 'is true when the watcher is running' do
        subject.start
        subject.running?.should be_true

        subject.stop
      end

      it 'is false when the watcher is not running' do
        subject.running?.should be_false

        subject.start
        subject.running?.should be_true

        subject.stop
        subject.running?.should be_false
      end
    end

    subject {
      watcher = DirectoryWatcher.new(@scratch_dir, options)
      DirectoryWatcherSpecs::Scenario.new(watcher)
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

    context 'run_once' do
      it "can be run on command via 'run_once'" do
        one_shot_file = scratch_path('run_once')

        subject.run_once_and_wait_for_event_count(1) do
          touch( one_shot_file )
        end.stop

        subject.events.should be_events_like( [[:added, 'run_once']] )
      end
    end

  end
end
