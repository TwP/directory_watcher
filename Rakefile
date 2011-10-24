
begin
  require 'bones'
rescue LoadError
  abort '### please install the "bones" gem ###'
end

Bones {
  name         'directory_watcher'
  summary      'A class for watching files within a directory and generating events when those files change'
  authors      'Tim Pease'
  email        'tim.pease@gmail.com'
  url          'http://rubygems.org/gems/directory_watcher'
  ignore_file  '.gitignore'

  spec.opts << "--color" << "--format documentation"

  # these are optional dependencies for runtime, adding one of them will provide
  # additional Scanner backends.
  depend_on  'rev'         , :development => true
  depend_on  'eventmachine', :development => true
  depend_on  'cool.io'     , :development => true

  depend_on 'bones-git'  , '~> 1.2.4', :development => true
  depend_on 'bones-rspec', '~> 2.0.1', :development => true
  depend_on 'rspec'      , '~> 2.7.0', :development => true
}

