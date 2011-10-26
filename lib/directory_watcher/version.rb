class DirectoryWatcher
  module Version
    def version
      File.read(path('version.txt')).strip
    end
    extend self
  end
end
