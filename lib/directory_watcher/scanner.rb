#
# The Scanner is responsible for polling the watched directory at a regular
# interval and generating events when files are modified, added or removed.
# These events are passed to the DirectoryWatcher which notifies the
# registered observers.
#
# The Scanner is a pure Ruby class, and as such it works across all Ruby
# interpreters on the major platforms. This also means that it can be
# processor intensive for large numbers of files or very fast update
# intervals. Your mileage will vary, but it is something to keep an eye on.
#
class DirectoryWatcher::Scanner
  include DirectoryWatcher::Threaded

  attr_accessor :glob
  attr_accessor :stable
  attr_accessor :files

  # call-seq:
  #    Scanner.new( opts = {} )
  #
  # Available options are:
  #
  #   :glob     - same as that in DirectoryWatcher
  #   :stable   - same as that in DirectoryWatcher
  #   :pre_load - same as that in DirectoryWatcher
  #   :interval - same as that in DirectoryWatcher
  #
  #   :event_queue - This is a Queue instance that the Scanenr will emit the
  #                  events too
  #
  # Generally all of them are required. The Scanner is not generally used out
  # side of a DirectoryWatcher so this is more of an internal API
  #
  def initialize( opts = {} )
    @glob = opts[:glob]
    @stable = opts[:stable]
    @pre_load = opts[:pre_load]
    @event_queue = opts[:event_queue]
    @files = Hash.new
    self.interval = opts[:interval]
  end

  # call-seq:
  #    reset( pre_load = false )
  #
  # Reset the scanner state by clearing the stored file list. Passing +true+
  # to this method will cause the file list to be pre-loaded after it has
  # been cleared effectively skipping the initial round of file added events
  # that would normally be generated.
  #
  def reset( pre_load = false )
    @files ||= Hash.new
    @files.merge!( scan_files ) if pre_load
  end

  # Before starting the run loop, we'll want to reset the system.
  #
  def before_starting
    reset( @pre_load )
  end

  # Performs exactly one scan of the directory for file changes and notifies
  # the observers.
  #
  def run
    files = scan_files
    keys = [files.keys, @files.keys]  # current files, previous files

    events  = find_added(files, *keys)
    events += find_modified(files, *keys)
    events += find_removed(*keys)

    notify( events )
    @files = files    # store the current file list for the next iteration
    self
  end

  private

  # Using the configured glob pattern, scan the directory for all files and
  # return a hash with the filenames as keys and +FileStat+ objects as the
  # values. The +FileStat+ objects contain the mtime and size of the file.
  #
  def scan_files
    files = {}
    @glob.each do |glob|
      Dir.glob(glob).each do |fn|
        begin
          stat = File.stat fn
          next unless stat.file?
          files[fn] = ::DirectoryWatcher::FileStat.new(stat.mtime, stat.size)
        rescue SystemCallError; end
      end
    end
    files
  end

  # call-seq:
  #    find_added( files, cur, prev )
  #
  # Taking the list of current files, _cur_, and the list of files found
  # previously, _prev_, figure out which files have been added and generate
  # a new file added event for each.
  #
  def find_added( files, cur, prev )
    added = cur - prev
    added.collect do |fn|
      files[fn].stable = @stable
      ::DirectoryWatcher::Event.new(:added, fn)
    end
  end

  # call-seq:
  #    find_removed( cur, prev )
  #
  # Taking the list of current files, _cur_, and the list of files found
  # previously, _prev_, figure out which files have been removed and
  # generate a new file removed event for each.
  #
  def find_removed( cur, prev )
    removed = prev - cur
    removed.collect {|fn| ::DirectoryWatcher::Event.new(:removed, fn) }
  end

  # call-seq:
  #    find_modified( files, cur, prev )
  #
  # Taking the list of current files, _cur_, and the list of files found
  # previously, _prev_, find those that are common between them and determine
  # if any have been modified. Generate a new file modified event for each
  # modified file. Also, by looking at the stable count in the _files_ hash,
  # figure out if any files have become stable since being added or modified.
  # Generate a new stable event for each stabilized file.
  #
  def find_modified( files, cur, prev )
    events = []
    (cur & prev).each do |key|
      cur_stat, prev_stat = files[key], @files[key]

      # if the modification time or the file size differs from the last
      # time it was seen, then create a :modified event
      if cur_stat != prev_stat
        events << ::DirectoryWatcher::Event.new(:modified, key)
        cur_stat.stable = @stable

      # otherwise, if the count is not nil see if we need to create a
      # :stable event
      elsif !prev_stat.stable.nil?
        cur_stat.stable = prev_stat.stable - 1
        if cur_stat.stable <= 0
          events << ::DirectoryWatcher::Event.new(:stable, key)
          cur_stat.stable = nil
        end
      end
    end
    return events
  end

  # Take all the current events, and send them to the notifier for delivery to
  # the observers.
  #
  def notify( events )
    until events.empty? do
      @event_queue.enq( events.shift )
    end
  end
end
