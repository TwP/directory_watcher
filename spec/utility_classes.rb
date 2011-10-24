module DirectoryWatcherSpecs
  # EventObserver just hangs out and collects all the events that are sent to it
  # It is used by the Scenario
  class EventObserver
    attr_reader :events
    def initialize
      @events = []
    end

    def update( *event_list )
      event_list.each { |e| @events << e }
    end
  end

  # Scenario is a utility to wrap up how to run a directory watcher scenario.
  # You would use it as such:
  #
  #   dws = Scenario.new( watcher )
  #   dws.do_after_events(2) do |scenario|
  #     # do something
  #   end.until_events(1)
  #
  # This will create a scenario, run the block after 2 events have been
  # collected, and then return again after 1 more event has been collected.
  #
  # You can then check the events with the custom matcher
  #
  #  dws.events.should be_events_like( ... )
  #
  class Scenario

    def initialize( watcher )
      @watcher = watcher
      @observer = EventObserver.new
      @watcher.add_observer( @observer )
      reset
    end

    def run_and_wait_for_event_count(count, &block )
      before_count = @observer.events.size
      @watcher.unpause
      yield self
      wait_for_events( before_count + count )
      return self
    end

    def run_and_wait_for_scan_count(count, &block)
      @watcher.unpause
      yield self
      wait_for_scan_count( count )
      return self
    end

    def events
      @observer.events
    end

    def stop
      @watcher.stop
    end

    def reset
      @observer.events.clear
      @watcher.start
      @watcher.pause
    end

    def run_once_and_wait_for_event_count( count, &block )
      @watcher.unpause
      @watcher.stop
      before_count = @observer.events.size
      yield self
      @watcher.run_once
      wait_for_events( before_count + count )
      return self
    end

    private

    def wait_for_events( limit )
      Thread.pass until @observer.events.size >= limit
    end

    def wait_for_scan_count( limit )
      @watcher.maximum_scans = limit
      Thread.pass until @watcher.finished_scans?
    end

  end
end
