class DirectoryWatcher
  # An +Event+ structure contains the _type_ of the event and the file _path_
  # to which the event pertains. The type can be one of the following:
  #
  #    :added      =>  file has been added to the directory
  #    :modified   =>  file has been modified (either mtime or size or both
  #                    have changed)
  #    :removed    =>  file has been removed from the directory
  #    :stable     =>  file has stabilized since being added or modified
  #
  class Event
    attr_reader :type
    attr_reader :path
    def initialize( type, path )
      @type = type
      @path = path
    end

    def to_s( )
      "#{type} '#{path}'" 
    end
  end
end
