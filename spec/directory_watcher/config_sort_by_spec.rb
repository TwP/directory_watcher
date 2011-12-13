
require 'spec_helper'

describe DirectoryWatcher do
  [ nil, :em, :coolio ].each do |scanner|

    let(:options) { default_options.merge(scanner: scanner) }

    subject {
      watcher = DirectoryWatcher.new(@scratch_dir, options)
      DirectoryWatcherSpecs::Scenario.new(watcher)
    }

    [:ascending, :descending].each do |ordering|

      let(:unique_values) { unique_sequence }

      context 'file name' do
        let(:filenames) { ('a'..'z').sort_by {rand} }
        let(:options) { default_options.merge(order_by: ordering) }

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

      context 'mtime' do

        let(:current_time) { Time.now }
        let(:filenames) { ('a'..'z').to_a.inject({}) { |h,k| h[k] = current_time - unique_values.next; h } }
        let(:options) { default_options.merge(sort_by: :mtime, order_by: ordering ) }

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

      context 'size' do
        let(:filenames) { ('a'..'z').to_a.inject({}) { |h,k| h[k] = unique_values.next; h } }
        let(:options) { default_options.merge( :sort_by => :size, :order_by => ordering ) }

        before do
          filenames.keys.sort_by{ rand }.each do |p|
            append_to( scratch_path(p), filenames[p] )
          end
        end

        it "#{ordering}" do
          subject.run_and_wait_for_event_count(filenames.size) { nil }
          sorted_fnames = filenames.to_a.sort_by { |k, v| v }
          final_events = sorted_fnames.map { |fn, ts| [:added, fn] }
          final_events.reverse! if ordering == :descending

          subject.events.should be_events_like( final_events )
        end
      end
    end
  end
end
