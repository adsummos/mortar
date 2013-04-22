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

require "erb"
require 'tempfile'
require "mortar/helpers"
require "mortar/local/installutil"

class Mortar::Local::Pig
  include Mortar::Local::InstallUtil

  PIG_LOG_FORMAT = "humanreadable"
  PIG_TAR_DEFAULT_URL = "https://s3.amazonaws.com/mhc-software-mirror/cli/pig.tgz"

  # Tempfile objects have a hook to delete the file when the object is
  # destroyed by the garbage collector.  In practice this means that a
  # file we want sitting around could disappear out from under us. To
  # prevent this behavior, we're keeping references to these objects so
  # that the garbage collector will not destroy them until the program
  # exits (and our files won't be deleted until we don't care about them
  # any more).
  @temp_file_objects

  # We copy some resources to the user's illustrate-output directory
  # for styling the output. This only happens if they are not already present.
  @resource_locations
  @resource_destinations

  attr_accessor :resource_locations
  attr_accessor :resource_destinations

  def initialize
    @temp_file_objects = []

    @resource_locations = { 
      "illustrate_template" => File.expand_path("../../templates/report/illustrate-report.html", __FILE__),
      "illustrate_css" => File.expand_path("../../../../css/illustrate.css", __FILE__),
      "jquery" => File.expand_path("../../../../js/jquery-1.7.1.min.js", __FILE__),
      "jquery_transit" => File.expand_path("../../../../js/jquery.transit.js", __FILE__),
      "jquery_stylestack" => File.expand_path("../../../../js/jquery.stylestack.js", __FILE__),
      "mortar_table" => File.expand_path("../../../../js/mortar-table.js", __FILE__),
      "zeroclipboard" => File.expand_path("../../../../js/zero_clipboard.js", __FILE__),
      "zeroclipboard_swf" => File.expand_path("../../../../flash/zeroclipboard.swf", __FILE__)
  }

  @resource_destinations = {
      "illustrate_html" => "illustrate-output/illustrate-output.html",
      "illustrate_css" => "illustrate-output/resources/css/illustrate-output.css",
      "jquery" => "illustrate-output/resources/js/jquery-1.7.1.min.js",
      "jquery_transit" => "illustrate-output/resources/js/jquery.transit.js",
      "jquery_stylestack" => "illustrate-output/resources/js/jquery.stylestack.js",
      "mortar_table" => "illustrate-output/resources/js/mortar-table.js",
      "zeroclipboard" => "illustrate-output/resources/js/zero_clipboard.js",
      "zeroclipboard_swf" => "illustrate-output/resources/flash/zeroclipboard.swf"
  }
  end

  def command
    return File.join(pig_directory, "bin", "pig")
  end

  def pig_directory
    return File.join(local_install_directory, "pig")
  end

  def pig_archive_url
    ENV.fetch('PIG_DISTRO_URL', PIG_TAR_DEFAULT_URL)
  end

  def pig_archive_file
    File.basename(pig_archive_url)
  end

  # Determines if a pig install needs to occur, true if no pig install present
  def should_do_pig_install?
    not (File.exists?(pig_directory))
  end

  # Determines if a pig install needs to occur, true if server side
  # pig tgz is newer than date of the existing install
  def should_do_pig_update?
    return is_newer_version('pig', pig_archive_url)
  end

  def install_or_update()
    call_install = false
    if should_do_pig_install?
      action "Installing pig" do
        install()
      end
    elsif should_do_pig_update?
      action "Updating to latest pig" do
        install()
      end
    end
  end

  # Installs pig for this project if it is not already present
  def install
    FileUtils.mkdir_p(local_install_directory)
    download_file(pig_archive_url, local_install_directory)
    local_tgz = File.join(local_install_directory, pig_archive_file)
    extract_tgz(local_tgz, local_install_directory)

    # This has been seening coming out of the tgz w/o +x so we do
    # here to be sure it has the necessary permissions
    FileUtils.chmod(0755, command)

    File.delete(local_tgz)
    note_install("pig")
  end

  def validate_script(pig_script, pig_parameters)
    run_pig_command(" -check #{pig_script.path}", pig_parameters)
  end


  # run the pig script with user supplied pig parameters
  def run_script(pig_script, pig_parameters)
    run_pig_command(" -f #{pig_script.path}", pig_parameters, true)
  end

  # Create a temp file to be used for writing the illustrate
  # json output, and return it's path. This data file will
  # later be used to create the result html output. Tempfile
  # will take care of cleaning up the file when we exit.
  def create_illustrate_output_path
    # Using Tempfile for the path generation and so that the
    # file will be cleaned up on process exit
    outfile = Tempfile.new("mortar-illustrate-output")
    outfile.close(false)
    outfile.path
  end

  # Given a file path, open it and decode the containing json
  def decode_illustrate_input_file(illustrate_outpath)
    data_raw = File.read(illustrate_outpath)
    begin
      data_encoded = data_raw.encode('UTF-8', 'binary', :invalid => :replace, :undef => :replace, :replace => '')
    rescue NoMethodError
      require 'iconv'
      ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
      data_encoded = ic.iconv(data_raw)
    end
    json_decode(data_encoded)
  end

  def show_illustrate_output(illustrate_outpath)
    ensure_dir_exists("illustrate-output")
    ensure_dir_exists("illustrate-output/resources")
    ensure_dir_exists("illustrate-output/resources/css")
    ensure_dir_exists("illustrate-output/resources/js")
    ensure_dir_exists("illustrate-output/resources/flash")

    ["illustrate_css",
     "jquery", "jquery_transit", "jquery_stylestack",
     "mortar_table", "zeroclipboard", "zeroclipboard_swf"].each { |resource|
      copy_if_not_present_at_dest(@resource_locations[resource], @resource_destinations[resource])
    }

    # Pull in the dumped json file
    illustrate_data = decode_illustrate_input_file(illustrate_outpath)

    # Render a template using it's values
    template_params = create_illustrate_template_parameters(illustrate_data)

    # template_params = {'tables' => []}
    erb = ERB.new(File.read(@resource_locations["illustrate_template"]), 0, "%<>")
    html = erb.result(BindingClazz.new(template_params).get_binding)

    # Write the rendered template out to a file
    File.open(@resource_destinations["illustrate_html"], 'w') { |f|
      f.write(html)
    }

    # Open a browser pointing to the rendered template output file
    action("Opening illustrate results from #{@resource_destinations["illustrate_html"]} ") do
      require "launchy"
      Launchy.open(File.expand_path(@resource_destinations["illustrate_html"]))
    end

  end

  def create_illustrate_template_parameters(illustrate_data)
    params = {}
    params['tables'] = illustrate_data['tables']
    params['udf_output'] = illustrate_data['udf_output']
    return params
  end

  def illustrate_alias(pig_script, pig_alias, skip_pruning, pig_parameters)
    cmd = "-e 'illustrate "

    # Parameters have to be entered with the illustrate command (as
    # apposed to as a command line argument) or it will result in an
    # 'Undefined parameter' error.
    param_file = make_pig_param_file(pig_parameters)
    cmd += "-param_file #{param_file} "

    # Now point us at the script/alias to illustrate
    illustrate_outpath = create_illustrate_output_path()
    cmd += "-script #{pig_script.path} -out #{illustrate_outpath} "
    
    if skip_pruning
      cmd += " -skipPruning "
    end

    if pig_alias
      cmd += " #{pig_alias} "
    end

    cmd += "'"

    result = run_pig_command(cmd, [], false)
    if result
      show_illustrate_output(illustrate_outpath)
    end
  end

  # Run pig with the specified command ('command' is anything that
  # can be appended to the command line invocation of Pig that will
  # get it to do something interesting, such as '-f some-file.pig'
  def run_pig_command(cmd, parameters = nil, jython_output = true)
    unset_hadoop_env_vars
    reset_local_logs
    # Generate the script for running the command, then
    # write it to a temp script which will be exectued
    script_text = script_for_command(cmd, parameters)
    script = Tempfile.new("mortar-")
    script.write(script_text)
    script.close(false)
    FileUtils.chmod(0755, script.path)
    system(script.path)
    script.unlink
    return (0 == $?.to_i)
  end

  # so Pig doesn't try to load the wrong hadoop jar/configuration
  # this doesn't mess up the env vars in the terminal, just this process (ruby)
  def unset_hadoop_env_vars
    ENV['HADOOP_HOME'] = ''
    ENV['HADOOP_CONF_DIR'] = ''
  end

  def reset_local_logs
    if Dir.exists? local_log_dir
      FileUtils.rm_rf local_log_dir
    end
    Dir.mkdir local_log_dir
    Dir.mkdir local_udf_log_dir
  end

  # Generates a bash script which sets up the necessary environment and
  # then runs the pig command
  def script_for_command(cmd, parameters, jython_output = true)
    template_params = pig_command_script_template_parameters(cmd, parameters)
    template_params['pig_opts']['jython.output'] = jython_output
    erb = ERB.new(File.read(pig_command_script_template_path), 0, "%<>")
    erb.result(BindingClazz.new(template_params).get_binding)
  end

  # Path to the template which generates the bash script for running pig
  def pig_command_script_template_path
    File.expand_path("../../templates/script/runpig.sh", __FILE__)
  end

  # Parameters necessary for rendering the bash script template
  def pig_command_script_template_parameters(cmd, pig_parameters)
    template_params = {}
    template_params['pig_params_file'] = make_pig_param_file(pig_parameters)
    template_params['pig_home'] = pig_directory
    template_params['pig_classpath'] = "#{pig_directory}/lib-pig/*:#{jython_directory}/jython.jar"
    template_params['classpath'] = "#{pig_directory}/lib/*:#{jython_directory}/jython.jar:#{pig_directory}/conf/jets3t.properties"
    template_params['project_home'] = File.expand_path("..", local_install_directory)
    template_params['local_install_dir'] = local_install_directory
    template_params['pig_sub_command'] = cmd
    template_params['pig_opts'] = pig_options
    template_params
  end

  # Returns a hash of settings that need to be passed
  # in via pig options
  def pig_options
    opts = {}
    opts['fs.s3n.awsAccessKeyId'] = ENV['AWS_ACCESS_KEY']
    opts['fs.s3n.awsSecretAccessKey'] = ENV['AWS_SECRET_KEY']
    opts['fs.s3.awsAccessKeyId'] = ENV['AWS_ACCESS_KEY']
    opts['fs.s3.awsSecretAccessKey'] = ENV['AWS_SECRET_KEY']
    opts['pig.events.logformat'] = PIG_LOG_FORMAT
    opts['pig.logfile'] = local_log_dir + "/local-pig.log"
    opts['pig.udf.scripting.log.dir'] = local_udf_log_dir
    opts['python.verbose'] = 'error'
    opts['jython.output'] = true
    opts['python.home'] = jython_directory
    opts['python.path'] = local_install_directory + "/../controlscripts"
    opts['python.cachedir'] = jython_cache_directory
    return opts
  end

  # Pig Paramenters that are supplied directly from Mortar when
  # running on the server side.  We duplicate these here.
  def automatic_pig_parameters
    params = {}
    if ENV['MORTAR_EMAIL_S3_ESCAPED']
      params['MORTAR_EMAIL_S3_ESCAPED'] = ENV['MORTAR_EMAIL_S3_ESCAPED']
    else
      params['MORTAR_EMAIL_S3_ESCAPED'] = Mortar::Auth.user_s3_safe
    end
    # Coerce into the same format as pig parameters that were
    # passed in via the command line or a parameter file
    param_list = []
    params.each{ |k,v|
      param_list.push({"name" => k, "value" => v})
    }
    return param_list
  end

  # Given a set of user specified pig parameters, combine with the
  # automatic mortar parameters and write out to a tempfile, returning
  # it's path so it may be referenced later in the process
  def make_pig_param_file(pig_parameters)
    mortar_pig_params = automatic_pig_parameters
    all_parameters = mortar_pig_params.concat(pig_parameters)
    param_file = Tempfile.new("mortar-pig-parameters")
    all_parameters.each { |p|
      param_file.write("#{p['name']}=#{p['value']}\n")
    }
    param_file.close(false)

    # Keep track a reference the tempfile object so that the
    # garbage collector does not automatically delete the file
    # out from under us
    @temp_file_objects.push(param_file)

    param_file.path
  end

  # Allows us to use a hash for template variables
  class BindingClazz
    def initialize(attrs)
      attrs.each{ |k, v|
        # set an instance variable with the key name so the binding will find it in scope
        self.instance_variable_set("@#{k}".to_sym, v)
      }
    end
    def get_binding()
      binding
    end
  end

end
