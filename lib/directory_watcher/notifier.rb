# Notifer pulls items from a queue and sends that item to ever observer
class DirectoryWatcher::Notifier
  include DirectoryWatcher::Threaded

  def initialize( queue, observers )
    @queue = queue
    @observers = observers
    self.interval = 0.01 # yes this is a fast loop
  end

  # Notify all the observers of all the available events in the queue.
  # If there are 2 or more events in a row that are the same, then they are
  # collapsed into a single event.
  #
  def run
    previous_event = nil
    until @queue.empty? do
      event = @queue.deq
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

  def send_event_to_observer( observer, func, event )
    observer.send(func, event)
  rescue Exception => e
    $stderr.puts "Called #{observer}##{func}(#{event}) and all I got was this lousy exception #{e}"
  end

end
