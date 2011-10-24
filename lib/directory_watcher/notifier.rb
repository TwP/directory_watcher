# Notifer pulls items from a queue and sends that item to ever observer
class DirectoryWatcher::Notifier
  include DirectoryWatcher::Threaded

  def initialize( queue, observers )
    @queue = queue
    @observers = observers
    self.interval = 0.01 # yes this is a fast loop
  end

  def run
    until @queue.empty? do
      event = @queue.deq
      @observers.each do |observer, func|
        begin
          observer.send(func, event)
        rescue Exception => e
          $stderr.puts "Called #{obsrever}##{func}(#{event}) and all I got was this lousy exception #{e}"
        end
      end
    end
  end

end
