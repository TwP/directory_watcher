require 'set'
# Collector reads items from a collection Queue and processes them to see if
# FileEvents should be put onto the notification Queue.
#
class DirectoryWatcher::Collector
  include DirectoryWatcher::Threaded
  include DirectoryWatcher::Logable

  # Create a new StatCollector from the given Configuration, and an optional
  # Scan.
  #
  # configuration - The Collector uses from Configuration:
  #   collection_queue   - The Queue to read items from the Scanner on
  #   notification_queue - The Queue to submit the Events to the Notifier on
  #   stable             - The number of times we see a file hasn't changed before
  #                        emitting a stable event
  #   sort_by            - the method used to sort events during on_scan results
  #   order_by           - The method used to order events from call to on_scan
  #
  # pre_load_scan - A Scan to use to load our internal state from before. No
  #                 events will be emitted for the FileStat's in this scan.
  #
  #def initialize( notification_queue, collection_queue, options = {} )
  def initialize( config )
    @stats = Hash.new
    @stable_counts = Hash.new(0)
    @config = config
    on_scan( DirectoryWatcher::Scan.new( config.glob ), false ) if config.pre_load?
    self.interval = 0.01 # yes this is a fast loop
  end

  # The number of times we see a file hasn't changed before emitting a stable
  # count. See Configuration#stable
  def stable_threshold
    @config.stable
  end

  # How to sort Scan results. See Configuration.
  #
  def sort_by
    @config.sort_by
  end

  # How to order Scan results. See Configuration.
  #
  def order_by
    @config.order_by
  end

  # The queue from which to read items from the scanners. See Configuration.
  #
  def collection_queue
    @config.collection_queue
  end

  # The queue to write Events for the Notifier. See Configuration.
  #
  def notification_queue
    @config.notification_queue
  end

  # Given the scan, update the set of stats with the results from the Scan and
  # emit events to the notification queue as appropriate.
  #
  # scan        - The Scan containing all the new FileStat items
  # emit_events - Should events be emitted for the events in the scan
  #               (default: true)
  #
  # Returns nothing.
  #
  # NOTE: Should ordering take place here?
  #
  def on_scan( scan, emit_events = true )
    seen_paths = Set.new
    logger.debug "Sorting by #{sort_by} #{order_by}"
    sorted_stats( scan.run ).each do |stat|
      on_stat(stat, emit_events)
      seen_paths << stat.path
    end
    emit_removed_events(seen_paths)
  end

  # Process a single stat and emit an event if necessary.
  #
  # stat       - The new FileStat to process and see if an event should
  #              be emitted
  # emit_event - Whether or not an event should be emitted.
  #
  # Returns nothing
  def on_stat( stat, emit_event = true )
    orig_stat = update_stat( stat )
    logger.debug "Emitting event for #{stat}"
    emit_event_for( orig_stat, stat ) if emit_event
  end

  # Remove one item from the collection queue and process it.
  #
  # This method is required by the Threaded API
  #
  # Returns nothing
  def run
    case thing = collection_queue.deq
    when ::DirectoryWatcher::Scan
      on_scan(thing)
    when ::DirectoryWatcher::FileStat
      on_stat(thing)
    else
      raise "Unknown item in the queue: #{thing}"
    end
  end

  # Write the current stats to the given IO object as a YAML document.
  #
  # io - The IO object to write the document to.
  #
  # Returns nothing.
  def dump_stats( io )
    YAML.dump(@stats, io)
  end

  # Read the current stats from the given IO object. Any existing stats in the
  # Collector will be overwritten
  #
  # io - The IO object from which to read the document.
  #
  # Returns nothing.
  def load_stats( io )
    @stats = YAML.load(io)
  end

  #######
  private
  #######

  # Sort the stats by +sort_by+ and +order_by+ returning the results
  #
  def sorted_stats( stats )
    sorted = stats.sort_by{ |stat| stat.send(sort_by) }
    sorted = sorted.reverse if order_by == :descending
    return sorted
  end

  # Update the stats Hash with the new_stat information, return the old data
  # that is being replaced.
  #
  def update_stat( new_stat )
    old_stat = @stats.delete(new_stat.path)
    @stats.store(new_stat.path, new_stat)
    return old_stat
  end

  # Look for removed files and emit removed events for all of them.
  #
  # seen_paths - the list of files that we know currently exist
  #
  # Return nothing
  def emit_removed_events( seen_paths )
    @stats.keys.each do |existing_path|
      next if seen_paths.include?(existing_path)
      old_stat = @stats.delete(existing_path)
      emit_event_for(old_stat, ::DirectoryWatcher::FileStat.for_removed_path(existing_path))
    end
  end

  # Determine what type of event to emit, and put that event onto the
  # notification queue.
  #
  # old_stat - The old FileStat
  # new_stat - The new FileStat
  #
  # Returns nothing
  def emit_event_for( old_stat, new_stat )
    event = DirectoryWatcher::Event.from_stats( old_stat, new_stat )
    notification_queue.enq event if should_emit?(event)
  end

  # Should the event given actually be emitted.
  #
  # If the event passed in is NOT a stable event, return true
  # If there is a stable_threshold, then check to see if the stable count for
  # this event's path has crossed the stable threshold.
  #
  # This method has the side effect of updating the stable count of the path of
  # the event. If we are going to return true for the stable event, then we
  # reset the stable count of that event to 0.
  #
  # event - any event
  #
  # Returns whether or not to emit the event based upon its stability
  def should_emit?( event )
    return true unless event.stable?
    if stable_threshold then
      @stable_counts[event.path] += 1
      logger.debug "stable_counts: #{@stable_counts[event.path]} threshold: #{stable_threshold}"
      if @stable_counts[event.path] >= stable_threshold then
        @stable_counts[event.path] = 0
        return true
      end
      return false
    end
  end
end
