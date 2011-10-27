# An +Event+ structure contains the _type_ of the event and the file _path_
# to which the event pertains. The type can be one of the following:
#
#    :added      =>  file has been added to the directory
#    :modified   =>  file has been modified (either mtime or size or both
#                    have changed)
#    :removed    =>  file has been removed from the directory
#    :stable     =>  file has stabilized since being added or modified
#
class DirectoryWatcher::Event

  attr_reader :type
  attr_reader :path

  # Create one of the 4 types of events given the two stats
  #
  # The rules are:
  #
  #   :added    => old_stat will be nil and new_stat will exist
  #   :removed  => old_stat will exist and new_stat will be nil
  #   :modified => old_stat != new_stat
  #   :stable   => old_stat == new_stat and
  #
  def self.from_stats( old_stat, new_stat )
    if old_stat != new_stat then
      return DirectoryWatcher::Event.new( :removed,  new_stat.path ) if new_stat.removed?
      return DirectoryWatcher::Event.new( :added,    new_stat.path ) if old_stat.nil?
      return DirectoryWatcher::Event.new( :modified, new_stat.path )
    else
      return DirectoryWatcher::Event.new( :stable, new_stat.path   )
    end
  end

  # Create a new Event with one of the 4 types and the path of the file.
  #
  def initialize( type, path )
    @type = type
    @path = path
  end

  def modified?
    type == :modified
  end

  def added?
    type == :added
  end

  def removed?
    type == :removed
  end

  def stable?
    type == :stable
  end

  def to_s( )
    "<#{self.class} type: #{type} path: '#{path}'>"
  end
end
