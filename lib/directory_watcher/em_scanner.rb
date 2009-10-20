
require 'thread'
require 'eventmachine'

[:epoll, :kqueue].each {|poll| break if EventMachine.send(poll)}

class DirectoryWatcher::EmScanner < ::DirectoryWatcher::Scanner

  class Watcher < EventMachine::FileWatch
    def initialize( scanner )
      @scanner = scanner
      @active = true
    end

    def stat
      return unless test ?e, @path
      stat = File.stat @path
      ::DirectoryWatcher::FileStat.new(stat.mtime, stat.size)
    end

    def active?() @active; end
    def event!() @scanner._event!(self); end
    def unbind() @active = false; end
    def file_deleted() EventMachine.next_tick {event!}; end

    alias :file_modified :event!
    alias :file_moved :event!
  end

  #
  #
  def initialize( &block )
    super(&block)
    @timer = nil
    @run_loop = lambda {run_loop}
    @watchers = {}
  end

  def running?
    !@timer.nil?
  end

  def start
    return if running?

    unless EventMachine.reactor_running?
      @thread = Thread.new {EventMachine.run}
      Thread.pass until EventMachine.reactor_running?
    end

    @files.keys.each do |fn|
      if test ?e, fn
        watch_file fn
        next
      end

      @files.delete fn
      @events << ::DirectoryWatcher::Event.new(:removed, fn)
    end

    run_loop
  end

  #
  #
  def stop
    return unless running?

    EventMachine.cancel_timer @timer rescue nil
    @timer = nil

    @watchers.each_value {|w| w.stop_watching if w.active?}
    @watchers.clear
  end

  # call-seq:
  #    join( limit = nil )
  #
  # This is a no-op method for the EventMachine file scanner.
  #
  def join( limit = nil )
  end

  #
  #
  def _event!( watcher )
    fn = watcher.path
    stat = watcher.stat

    if stat
      watch_file fn unless watcher.active?
      @events << ::DirectoryWatcher::Event.new(:modified, fn)
    else
      if watcher.active?
        watcher.stop_watching
        @watchers.delete fn
      end
      @files.delete fn
      @events << ::DirectoryWatcher::Event.new(:removed, fn)
    end

    notify
  end
 

  private

  # Using the configured glob pattern, scan the directory for all files and
  # return an array of the filenames found.
  #
  def list_files
    files = []
    @glob.each do |glob|
      Dir.glob(glob).each {|fn| files << fn if test ?f, fn}
    end
    files
  end

  #
  #
  def run_loop
    start = Time.now.to_f

    _find_added
    _find_stable

    notify

    nap_time = @interval - (Time.now.to_f - start)
    nap_time = 0.001 unless nap_time > 0
    @timer = EventMachine.add_timer nap_time, @run_loop
  end

  #
  #
  def _find_added
    cur = list_files
    prev = @files.keys
    added = cur - prev

    added.each do |fn|
      stat = File.stat fn
      @files[fn] = ::DirectoryWatcher::FileStat.new(stat.mtime, stat.size, @stable)
      @events << ::DirectoryWatcher::Event.new(:added, fn)
      watch_file fn
    end
  end

  #
  #
  def _find_stable
    @files.each do |key, stat|
      next if stat.stable.nil?
      stat.stable -= 1
      if stat.stable <= 0
        @events << ::DirectoryWatcher::Event.new(:stable, key)
        stat.stable = nil
      end
    end
  end

  def watch_file( fn )
    @watchers[fn] = EventMachine.watch_file fn, Watcher, self
  end

end  # class DirectoryWatcher::EmScanner

# EOF
