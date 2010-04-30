
begin
  require 'fsevent'
  require 'thread'
  DirectoryWatcher::HAVE_FSEVENT = true
rescue LoadError
  DirectoryWatcher::HAVE_FSEVENT = false
end

if DirectoryWatcher::HAVE_FSEVENT

# The FSEvent scanner is only availabe on Max OS X systems running version
# 10.5 or greater of the OS (Leopard and Snow Leopard). You must install the
# ruby-fsevent gem to use the FSEvent scanner.
#
class DirectoryWatcher::FseventScanner < DirectoryWatcher::Scanner

  # call-seq:
  #    FseventScanner.new { |events| block }
  #
  # Create an FSEvent based scanner that will generate file events and pass
  # those events (as an array) to the given _block_.
  #
  def initialize( &block )
    super(&block)

    @mutex = Mutex.new
    @directories = Array.new
    @notifier = Notifier.new self
  end

  # Start the scanner thread. If the scanner is already running, this method
  # will return without taking any action.
  #
  def start
    return if running?

    @stop = false
    @thread = Thread.new(self) {|scanner| scanner.__send__ :run_loop}
    Thread.new { @notifier.start }
    self
  end

  # Stop the scanner thread. If the scanner is already stopped, this method
  # will return without taking any action.
  #
  def stop
    return unless running?

    @stop = true
    @notifier.stop
    @thread.join
    self
  ensure
    @thread = nil
  end

  def glob=( value )
    @glob_hash = (@glob_hash || Hash.new {|h,k| h[k] = Array.new}).clear
    @glob = value.map {|g| File.expand_path(g)}

    @glob.each do |g|
      dir = File.dirname(g) << File::SEPARATOR
      if dir =~ %r/\*\*/
        g = File.basename(g)
        Dir[dir].each {|d| @glob_hash[d] << g}
      else
        @glob_hash[dir] << File.basename(g)
      end
    end

    @glob_hash.each_value {|ary| ary.uniq!}
  end

  def _add( directories )
    @mutex.synchronize { @directories.concat directories }
  end


private

  # Calling this method will enter the scanner's run loop. The
  # calling thread will not return until the +stop+ method is called.
  #
  # The run loop is responsible for scanning the directory for file changes,
  # and then dispatching events to registered listeners.
  #
  def run_loop
    loop do
      break if @stop
      run_once

      @mutex.synchronize {
        @signal -= 1 if @signal > 0
        next if @signal > 0
        @ready.wait(@mutex)
      }
    end
  end

  #
  #
  def directories
    rv = nil
    @mutex.synchronize {
      rv = @directories.dup
      @directories.clear
    }
    rv.sort!.uniq!
    rv
  end

  # :stopdoc:
  class Notifier < FSEvent
    def initialize( scanner )
      super()
      @scanner = scanner
      watch directories
    end
    alias :watch :watch_directories

    def on_change( directories )
      @scanner._add directories
    end
  end
  # :startdoc:

end  # class DirectoryWatcher::FseventScanner
end  # if HAVE_FSEVENT

