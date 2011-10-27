require 'spec_helper'

describe DirectoryWatcher::Paths do
  it "has a libpath" do
    DirectoryWatcher.lib_path.should == File.expand_path( "../../lib", __FILE__) + ::File::SEPARATOR
  end
end
