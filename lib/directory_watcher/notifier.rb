# A Notifier pull Event instances from the give queue and sends them to all of
# the Observers it knows about.
#
class DirectoryWatcher::Notifier
  include DirectoryWatcher::Threaded
  include DirectoryWatcher::Logable

  # Create a new Notifier that pulls events off the given notification_queue from the
  # config, and sends them to the listed observers.
  #
  def initialize( config, observers )
    @config = config
    @observers = observers
    self.interval = 0.01 # yes this is a fast loop
  end

  # Notify all the observers of all the available events in the queue.
  # If there are 2 or more events in a row that are the same, then they are
  # collapsed into a single event.
  #
  def run
    previous_event = nil
    until queue.empty? do
      event = queue.deq
      next if previous_event == event
      @observers.each do |observer, func|
        send_event_to_observer( observer, func, event )
      end
      previous_event = event
    end
  end

  #######
  private
  #######

  def queue
    @config.notification_queue
  end

  # Send the given event to the given observer using the given function.
  #
  # Capture any exceptions that have, swallow them and send them to stderr.
  def send_event_to_observer( observer, func, event )
    observer.send(func, event)
  rescue Exception => e
    $stderr.puts "Called #{observer}##{func}(#{event}) and all I got was this lousy exception #{e}"
  end
end
