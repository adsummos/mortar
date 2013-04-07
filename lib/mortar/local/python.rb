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

require "mortar/local/installutil"

class Mortar::Local::Python
  include Mortar::Local::InstallUtil

  PYTHON_DEFAULT_TGZ_URL = "https://s3.amazonaws.com/mhc-software-mirror/cli/mortar-python-osx.tgz"

  # Path to the python binary that should be used
  # for running UDFs
  @command = nil


  # Execute either an installation of python or an inspection
  # of the local system to see if a usable python is available
  def check_or_install
    if osx?
      # We currently only install python for osx
      install_or_update_osx
    else
      # Otherwise we check that the system supplied python will be sufficient
      check_system_python
    end
  end

  def should_do_update?
    return is_newer_version('python', python_archive_url)
  end

  # Performs an installation of python specific to this project, this
  # install includes pip and virtualenv
  def install_or_update_osx
    @command = "#{local_install_directory}/python/bin/python"
    if should_do_python_install?
      action "Installing python" do
        install_osx
      end
    elsif should_do_update?
      action "Updating to latest python" do
        install_osx
      end
    end
    true
  end

  def install_osx
    FileUtils.mkdir_p(local_install_directory)
    download_file(python_archive_url, local_install_directory)
    extract_tgz(local_install_directory + "/" + python_archive_file, local_install_directory)

    # This has been seening coming out of the tgz w/o +x so we do
    # here to be sure it has the necessary permissions
    FileUtils.chmod(0755, @command)
    File.delete(local_install_directory + "/" + python_archive_file)
    note_install("python")
  end

  # Determines if a python install needs to occur, true if no
  # python install present or a newer version is available
  def should_do_python_install?
    return (osx? and (not (File.exists?(python_directory))))
  end


  # Checks if there is a usable versionpython already installed
  def check_system_python
    py_cmd = path_to_local_python()
    if not py_cmd
      false
    else
      @command = py_cmd
      true
    end
  end

  # Checks if the specified python command has
  # virtualenv installed
  def check_virtualenv_installed(python)
    `#{python} -m virtualenv --help`
    if (0 != $?.to_i)
      false
    else
      true
    end
  end

  def path_to_local_python
    # Check several python commands in decending level of desirability
    [ "python#{desired_python_minor_version}", "python" ].each{ |cmd|
      path_to_python = `which #{cmd}`.to_s.strip
      if path_to_python != ''
        # todo: check for a minimum version (in the case of 'python')
        if check_virtualenv_installed(path_to_python)
          return path_to_python
        end
      end
    }
    return nil
  end


  def desired_python_minor_version
    return "2.7"
  end

  def pip_requirements_path
    return ENV.fetch('PIP_REQ_FILE', File.join(Dir.getwd, "udfs", "python", "requirements.txt"))
  end

  def has_python_requirements
    return File.exists?(pip_requirements_path)
  end

  def python_env_dir
    return "#{local_install_directory}/pythonenv"
  end

  def python_directory
    return "#{local_install_directory}/python"
  end

  def python_archive_url
    return ENV.fetch('PYTHON_DISTRO_URL', PYTHON_DEFAULT_TGZ_URL)
  end

  def python_archive_file
    File.basename(python_archive_url)
  end

  # Creates a virtualenv in a well known location and installs any packages
  # necessary for the users python udf
  def setup_project_python_environment
    `#{@command} -m virtualenv #{python_env_dir}`
    if 0 != $?.to_i
      return false
    end
    if should_do_requirements_install
      action "Installing python UDF dependencies" do
        pip_output = `. #{python_env_dir}/bin/activate &&
          #{python_env_dir}/bin/pip install --requirement #{pip_requirements_path}`
          if 0 != $?.to_i
            File.open(pip_error_log_path, 'w') { |f|
              f.write(pip_output)
            }
            return false
          end
        note_install("pythonenv")
      end
    end
    return true
  end

  def pip_error_log_path
    return ENV.fetch('PIP_ERROR_LOG', "dependency_install.log")
  end

  # Whether or not we need to do a `pip install -r requirements.txt` because
  # we've never done one before or the dependencies have changed
  def should_do_requirements_install
    if has_python_requirements
      if not install_date('pythonenv')
        # We've never done an install from requirements.txt before
        return true
      else
        return (requirements_edit_date > install_date('pythonenv'))
      end
    else
      return false
    end
  end

  # Date of last change to the requirements file
  def requirements_edit_date
    if has_python_requirements
      return File.mtime(pip_requirements_path).to_i
    else
      return nil
    end
  end

end
