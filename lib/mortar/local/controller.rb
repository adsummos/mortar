#
# Copyright 2012 Mortar Data Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "mortar/helpers"
require "mortar/local/pig"
require "mortar/local/java"
require "mortar/local/python"
require "mortar/local/jython"


class Mortar::Local::Controller
  include Mortar::Local::InstallUtil

  NO_JAVA_ERROR_MESSAGE = <<EOF
A suitable java installation could not be found.  If you already have java installed
please set your JAVA_HOME environment variable before continuing.  Otherwise, a
suitable java installation will need to be added to your local system.

Installing Java
On OSX run `javac` from the command line.  This will intiate the installation.  For
Linux systems please consult the documentation on your relevant package manager.
EOF

  NO_PYTHON_ERROR_MESSAGE = <<EOF
A suitable python installation with virtualenv could not be located.  Please ensure
you have python 2.6+ installed on your local system.  If you need to obtain a copy
of virtualenv it can be located here:
https://pypi.python.org/pypi/virtualenv
EOF

  NO_AWS_KEYS_ERROR_MESSAGE = <<EOF
Please specify your aws access key via environment variable AWS_ACCESS_KEY
and your aws secret key via environment variable AWS_SECRET_KEY"
EOF


  # Checks if the user has properly specified their AWS keys
  def verify_aws_keys()
    if (not (ENV['AWS_ACCESS_KEY'] and ENV['AWS_SECRET_KEY'])) then
      if not ENV['MORTAR_IGNORE_AWS_KEYS']
        return false
      else
        return true
      end
    else
      return true
    end
  end

  # Exits with a helpful message if the user has not setup their aws keys
  def require_aws_keys()
    unless verify_aws_keys()
      error(NO_AWS_KEYS_ERROR_MESSAGE)
    end
  end

  # Main entry point to perform installation and configuration necessary
  # to run pig on the users local machine
  def install_and_configure
    java = Mortar::Local::Java.new()
    unless java.check_install
      error(NO_JAVA_ERROR_MESSAGE)
    end

    pig = Mortar::Local::Pig.new()
    pig.install_or_update()

    py = Mortar::Local::Python.new()
    unless py.check_or_install
      error(NO_PYTHON_ERROR_MESSAGE)
    end

    unless py.setup_project_python_environment
      msg = "\nUnable to setup a python environment with your dependencies, "
      msg += "see #{py.pip_error_log_path} for more details"
      error(msg)
    end

    jy = Mortar::Local::Jython.new()
    jy.install_or_update()

    ensure_local_install_dir_in_gitignore
  end

  def ensure_local_install_dir_in_gitignore()
    if File.exists? local_project_gitignore
      open(local_project_gitignore, 'r+') do |gitignore|
        unless gitignore.read().include? local_install_directory_name
          gitignore.seek(0, IO::SEEK_END)
          gitignore.puts local_install_directory_name
        end
      end
    end
  end

  # Main entry point for user running a pig script
  def run(pig_script, pig_parameters)
    require_aws_keys
    install_and_configure
    pig = Mortar::Local::Pig.new()
    pig.run_script(pig_script, pig_parameters)
  end

  # Main entry point for illustrating a pig alias
  def illustrate(pig_script, pig_alias, pig_parameters, skip_pruning)
    require_aws_keys
    install_and_configure
    pig = Mortar::Local::Pig.new()
    pig.illustrate_alias(pig_script, pig_alias, skip_pruning, pig_parameters)
  end

  def validate(pig_script, pig_parameters)
    install_and_configure
    pig = Mortar::Local::Pig.new()
    pig.validate_script(pig_script, pig_parameters)
  end

end
