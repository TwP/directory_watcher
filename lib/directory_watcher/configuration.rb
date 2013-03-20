#
# The top level configuration options used by DirectoryWatcher are used by many
# of the sub components for a variety of purposes. The Configuration represents
# all those options and other global like instances.
#
# The top level DirectoryWatcher class allows the configs to be changed during
# execution, so all of the dependent classes need to be informed when their
# options have changed. This class allows that.
#
class DirectoryWatcher::Configuration
  # The directory to monitor for events. The glob's will be used in conjunction
  # with this directory to find the full list of globs available.
  attr_reader :dir

  # The glob of files to monitor. This is an Array of file matching globs
  # be aware that changing the :glob value after watching has started has the
  # potential to cause spurious events if the new globs do not match the old,
  # files will appear to have been deleted.
  #
  # The default is '*'
  attr_reader :glob

  # The interval at which to do a full scan using the +glob+ to determine Events
  # to send.
  #
  # The default is 30.0 seconds
  attr_reader :interval

  # Controls the number of intervals a file must remain unchanged before it is
  # considered "stable". When this condition is met, a stable event is
  # generated for the file. If stable is set to +nil+ then stable events
  # will not be generated.
  #
  # The default is nil, indicating no stable events are to be emitted.
  attr_reader :stable

  # pre_load says if an initial scan using the globs should be done to pre
  # populate the state of the system before sending any events.
  #
  # The default is false
  attr_reader :pre_load

  # The filename to persist the state of the DirectoryWatcher too upon calling
  # *stop*.
  #
  # The default is nil, indicating that no state is to be persisted.
  attr_reader :persist

  # The back end scanner to use. The available options are:
  #
  #   nil     => Use the default, pure ruby Threaded scanner
  #   :em     => Use the EventMachine based scanner. This requires that the
  #              'eventmachine' gem be installed.
  #   :coolio => Use the Cool.io based scanner. This requires that the
  #              'cool.io' gem be installed.
  #   :rev    => Use the Rev based scanner. This requires that the 'rev' gem be
  #              installed.
  #
  # The default is nil, indicating the pure ruby threaded scanner will be used.
  # This option may not be changed once the DirectoryWatcher is allocated.
  #
  attr_reader :scanner

  # The sorting method to use when emitting a set of Events after a Scan has
  # happened. Since a Scan may produce a number of events, if those Events should
  # be emitted in a particular order, use +sort_by+ to pick which field to sort
  # the events, and +order_by+ to say if those events are to be emitted in
  # :ascending or :descending order.
  #
  # Available options:
  #
  #   :path   => The default, they will be sorted by full pathname
  #   :mtime  => Last modified time. They will be sorted by their FileStat mtime
  #   :size   => The number of bytes in the file.
  #
  attr_accessor :sort_by

  # When sorting you may pick if the order should be:
  #
  #   :ascending  => The default, from lowest to highest
  #   :descending => from highest to lowest.
  #
  attr_accessor :order_by

  # The Queue through which the Scanner will send data to the Collector
  #
  attr_reader :collection_queue

  # The Queue through which the Collector will send data to the Notifier
  #
  attr_reader :notification_queue

  # The logger through wich every one will log
  #
  attr_reader :logger

  # Return a Hash of all the default options
  #
  def self.default_options
    {
      :dir           => '.',
      :glob          => '*',
      :interval      => 30.0,
      :stable        => nil,
      :pre_load      => false,
      :persist       => nil,
      :scanner       => nil,
      :sort_by       => :path,
      :order_by      => :ascending,
      :logger        => nil,
    }
  end

  # Create a new Configuration by blending the passed in items with the defaults
  #
  def initialize( options = {} )
    o = self.class.default_options.merge( options )
    @dir      = o[:dir]
    @pre_load = o[:pre_load]
    @scanner  = o[:scanner]
    @sort_by  = o[:sort_by]
    @order_by = o[:order_by]

    # These have validation rules
    self.persist = o[:persist]
    self.interval = o[:interval]
    self.glob = o[:glob]
    self.stable = o[:stable]
    self.logger = o[:logger]

    @notification_queue = Queue.new
    @collection_queue = Queue.new
  end

  # Is pre_load set or not
  #
  def pre_load?
    @pre_load
  end

  # The class of the scanner
  #
  def scanner_class
    class_name = scanner.to_s.capitalize + 'Scanner'
    DirectoryWatcher.const_get( class_name ) rescue DirectoryWatcher::Scanner
  end

  # call-seq:
  #    glob = '*'
  #    glob = ['lib/**/*.rb', 'test/**/*.rb']
  #
  # Sets the glob pattern that will be used when scanning the directory for
  # files. A single glob pattern can be given or an array of glob patterns.
  #
  def glob=( val )
    glob = case val
           when String; [File.join(@dir, val)]
           when Array; val.flatten.map! {|g| File.join(@dir, g)}
           else
             raise(ArgumentError,
                   'expecting a glob pattern or an array of glob patterns')
           end
    glob.uniq!
    @glob = glob
  end

  # Sets the directory scan interval. The directory will be scanned every
  # _interval_ seconds for changes to files matching the glob pattern.
  # Raises +ArgumentError+ if the interval is zero or negative.
  #
  def interval=( val )
    val = Float(val)
    raise ArgumentError, "interval must be greater than zero" if val <= 0
    @interval = val
  end

  # Sets the logger instance. This will be used by all classes for logging
  #
  def logger=( val )
    if val then
      if %w[ debug info warn error fatal ].all? { |meth| val.respond_to?( meth ) } then
        @logger = val
      end
    else
      @logger = ::DirectoryWatcher::Logable.default_logger
    end
  end

  # Sets the number of intervals a file must remain unchanged before it is
  # considered "stable". When this condition is met, a stable event is
  # generated for the file. If stable is set to +nil+ then stable events
  # will not be generated.
  #
  # A stable event will be generated once for a file. Another stable event
  # will only be generated after the file has been modified and then remains
  # unchanged for _stable_ intervals.
  #
  # Example:
  #
  #     dw = DirectoryWatcher.new( '/tmp', :glob => 'swap.*' )
  #     dw.interval = 15.0
  #     dw.stable = 4
  #
  # In this example, a directory watcher is configured to look for swap files
  # in the /tmp directory. Stable events will be generated every 4 scan
  # intervals iff a swap remains unchanged for that time. In this case the
  # time is 60 seconds (15.0 * 4).
  #
  def stable=( val )
    if val.nil?
      @stable = nil
    else
      val = Integer(val)
      raise ArgumentError, "stable must be greater than zero" if val <= 0
      @stable = val
    end
    return @stable
  end

  # Sets the name of the file to which the directory watcher state will be
  # persisted when it is stopped. Setting the persist filename to +nil+ will
  # disable this feature.
  #
  def persist=( filename )
    @persist = filename ? filename.to_s : nil
  end
end

