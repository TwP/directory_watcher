require 'spec_helper'

describe DirectoryWatcher::Scan do

  it 'should ignore file matched by ignore_glob' do
    pending

    scratch_path('test/file1.rb')
    scan = DirectoryWatcher::Scan.new('**/*.rb')

    scan.run.should == ['a']
  end

end
