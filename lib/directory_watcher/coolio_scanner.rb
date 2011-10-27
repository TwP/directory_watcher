begin
  require 'coolio'
  DirectoryWatcher::HAVE_COOLIO = true
rescue LoadError
  DirectoryWatcher::HAVE_COOLIO = false
end

if DirectoryWatcher::HAVE_COOLIO

# The CoolioScanner uses the Coolio loop to monitor changes to files in the
# watched directory. This scanner is more efficient than the pure Ruby
# scanner because it relies on the operating system kernel notifictions
# instead of a periodic polling and stat of every file in the watched
# directory (the technique used by the Scanner class).
#
class DirectoryWatcher::CoolioScanner < ::DirectoryWatcher::Scanner
  # call-seq:
  #    CoolioScanner.new( options )
  #
  # Create a Coolio based scanner that will generate file events and pass
  # those events (as an array) to the given _block_.
  #
  def initialize( options = {})
    super(options)
    @watchers = {}
    @timer = nil
    @cio_thread = nil
    @paused = false
  end

  def running?
    !@timer.nil?
  end

  def pause
    @timer.disable if @timer.enabled?
    @watchers.each_value { |w| w.disable if w.enabled? }
    @paused = true
  end

  def resume
    @timer.enable unless @timer.enabled?
    @watchers.each_value { |w| w.enable unless w.enabled? }
    @paused = false
  end

  def paused?
    @paused
  end

  def before_starting
    super
    setup_existing_watches_and_alert_removed
    @timer = PeriodicTimer.new(self)
    @timer.attach(@cio_thread._coolio_loop)
  end

  # Start the Coolio scanner loop. If the scanner is already running, this method
  # will return without taking any action.
  #
  def start
    return if running?

    before_timer = BeforeTimer.new self
    @cio_thread = Thread.new {
      coolio_loop = Thread.current._coolio_loop
      before_timer.attach(coolio_loop)
      coolio_loop.run
    }
  end


  def stop
    return unless running?
    @stopping = true
    teardown_timer_and_watches
    @stopping = false
    if @cio_thread then
      @cio_thread._coolio_loop.stop rescue nil 
      @cio_thread.kill
      @cio_thread = nil
    end
  end

  # :stopdoc:
  #
  # This callback is invoked by a Watcher instance when some change has
  # occured on the file. The scanner determines if the file has been
  # modified or deleted and notifies the directory watcher accordingly.
  #
  def on_change(watcher, new_stat)
    return if paused?
    fn = watcher.path
    prev_stat = @files[fn]

    if File.exist?( fn ) then
      if prev_stat != new_stat then
        @files[fn] = new_stat
        notify(::DirectoryWatcher::Event.new(:modified, fn))
      end
    else
      watcher.detach
      @watchers.delete(fn)
      @files.delete(fn)
      notify(::DirectoryWatcher::Event.new(:removed, fn))
    end
  end

  # This callback is invoked by the Timer instance when it is triggered by
  # the Coolio loop. This method will check for added files and stable files
  # and notify the directory watcher accordingly.
  #
  def on_timer
    notify_added_and_stable
    progress_towards_maximum_iterations
  end

  # Setting maximum iterations means hooking into the periodic timer event and
  # counting the number of times it is going on. This also resets the current
  # iterations count
  #
  def maximum_iterations=(value)
    unless value.nil?
      value = Integer(value)
      raise ArgumentError, "maximum iterations must be >= 1" unless value >= 1
    end
    @iterations = 0
    @maximum_iterations = value
  end
  attr_reader :maximum_iterations
  attr_reader :iterations

  #######
  private
  #######

  # Before the peridic timers are kicked off and we start using the event loop
  # proper, we need to setup file watches on all the existing files. This is
  # because pre_load may have happened and we need to watch those files. And
  # some of those files may have disappared from the time of the scan to the
  # time we are called
  #
  def setup_existing_watches_and_alert_removed
    events = []
    to_watch = []
    files.keys.each do |fn|
      if File.exist?( fn ) then
        to_watch << fn
      else
        files.delete fn
        events << ::DirectoryWatcher::Event.new(:removed, fn)
      end
    end
    # do this so that the notifications for removed files will probably go out
    # before anything that might happen to the watched files.
    notify(events) unless events.empty?

    to_watch.each { |fn| watch_file(fn) }
  end

 
  def teardown_timer_and_watches
    @timer.detach rescue nil
    @timer = nil

    @watchers.each_value {|w| w.detach}
    @watchers.clear
  end


  # Create and return a new Watcher instance for the given filename _fn_.
  #
  def watch_file( fn )
    w = Watcher.new(fn, self)
    w.attach(coolio_loop)
    @watchers[fn] = w
  end

  def coolio_loop
    if @cio_thread then
      @cio_thread._coolio_loop
    else
      Thread.current._coolio_loop
    end
  end

  def notify_added_and_stable
    return if paused?
    events = []
    scan_files.each do |fn, new_stat|
      if cached_stat = @files[fn] then
        if stable_event?( cached_stat, new_stat ) then
          events << ::DirectoryWatcher::Event.new(:stable, fn)
        end
      else
        @files[fn] = watch_file(fn).stat
        events << ::DirectoryWatcher::Event.new(:added, fn)
      end
    end
    notify(events)
  end

  # Make progress towards maximum iterations. And if we get there, then stop
  # monitoring files.
  #
  def progress_towards_maximum_iterations
    if maximum_iterations then
      @iterations += 1
      stop if finished_iterations?
    end
  end

  # have we finished the maximum number of iterations we should
  #
  def finished_iterations?
    self.iterations >= self.maximum_iterations
  end

  # Return whether or not the two stats are the same, and if they are the same
  # should a stable event be issued.
  #
  def stable_event?( cur_stat, new_stat )
    if cur_stat == new_stat and !cur_stat.stable.nil? then
      cur_stat.stable -= 1
      if cur_stat.stable <= 0 then
        cur_stat.stable = nil
        return true
      end
    end
    return false
  end

  # :stopdoc:
  #
  class Watcher < Coolio::StatWatcher
    def initialize( fn, scanner )
      super(fn, scanner.interval)
      @scanner = scanner
    end

    def on_change( prev_stat, current_stat )
      new_stat = ::DirectoryWatcher::FileStat.new(current_stat.mtime, current_stat.size, @scanner.stable)
      @scanner.on_change(self, new_stat)
    end

    def stat
      return unless test ?e, path
      stat = File.stat path
      ::DirectoryWatcher::FileStat.new(stat.mtime, stat.size, @scanner.stable)
    end
  end

  class BeforeTimer < Coolio::TimerWatcher
    def initialize( scanner )
      super(scanner.interval, false)
      @scanner = scanner
    end

    def on_timer( *args )
      @scanner.before_starting
    end
  end

  class PeriodicTimer < Coolio::TimerWatcher
    def initialize( scanner )
      super(scanner.interval, true)
      @scanner = scanner
    end

    def on_timer( *args )
      @scanner.on_timer
    end
  end
  # :startdoc:


end  # class DirectoryWatcher::CoolioScanner

end  # if DirectoryWatcher::HAVE_COOLIO

# EOF
