
begin
  require 'bones'
rescue LoadError
  abort '### please install the "bones" gem ###'
end

ensure_in_path 'lib'
require 'directory_watcher'

Bones {
  name         'directory_watcher'
  summary      'A class for watching files within a directory and generating events when those files change'
  authors      'Tim Pease'
  email        'tim.pease@gmail.com'
  url          'http://gemcutter.org/gems/directory_watcher'
  version      DirectoryWatcher::VERSION
  ignore_file  '.gitignore'

  rubyforge.name  'codeforpeople'

  depend_on  'rev',          :development => true
  depend_on  'eventmachine', :development => true
}

