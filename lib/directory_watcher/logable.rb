class DirectoryWatcher

  # This is the implementation of a logger that does nothing.
  # It has all the debug, info, warn, error, fatal methods, but they do nothing
  class NullLogger
    def debug( msg ); end
    def info( msg );  end
    def warn( msg );  end
    def error( msg ); end
    def fatal( msg ); end
  end

  module Logable
    def logger
      @config.logger
    end

    def self.default_logger
      require 'logging'
      Logging::Logger[DirectoryWatcher]
    rescue LoadError
      NullLogger.new
    end
  end

end
