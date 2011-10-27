class DirectoryWatcher
  module Version
    def version
      File.read(DirectoryWatcher.path('version.txt')).strip
    end
    extend self
  end
end
