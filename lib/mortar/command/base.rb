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
# Portions of this code from heroku (https://github.com/heroku/heroku/) Copyright Heroku 2008 - 2012,
# used under an MIT license (https://github.com/heroku/heroku/blob/master/LICENSE).
#

require "fileutils"
require "mortar/auth"
require "mortar/command"
require "mortar/project"
require "mortar/git"

class Mortar::Command::Base
  include Mortar::Helpers

  def self.namespace
    self.to_s.split("::").last.downcase
  end

  attr_reader :args
  attr_reader :options

  def initialize(args=[], options={})
    @args = args
    @options = options
  end

  def project
    unless @project
      project_name, project_dir, remote = 
      if project_from_dir = extract_project_in_dir()
        [project_from_dir[0], Dir.pwd, project_from_dir[1]]
      elsif project_from_dir = extract_project_in_dir_no_git()
        [project_from_dir[0], Dir.pwd, project_from_dir[1]]
      else
        raise Mortar::Command::CommandFailed, "No project found.\nThis command must be run from within a project folder."
      end
      
      # if we only have a project name, look for the remote in the current dir
      unless remote
        if project_from_dir = extract_project_in_dir(project_name)
          project_dir = Dir.pwd
          remote = project_from_dir[1]
        end
      end
      
      @project = Mortar::Project::Project.new(project_name, project_dir, remote)
    end
    @project
  end
  
  def api
    Mortar::Auth.api
  end
  
  def git
    @git ||= Mortar::Git::Git.new
  end
  
  def pig_parameters
    paramfile_params = {}
    if options[:param_file]
      File.open(options[:param_file], "r").each do |line|
        # If the line isn't empty
        if not line.chomp.empty? and not line.chomp.match(/^;/)
          name, value = line.split('=', 2)
          if not name or not value
            error("Parameter file is malformed")
          end
          paramfile_params[name] = value
        end
      end
    end
    
    
    paramoption_params = {}
    input_parameters = options[:parameter] ? Array(options[:parameter]) : []
    input_parameters.each do |name_equals_value|
      name, value = name_equals_value.split('=', 2)
      paramoption_params[name] = value
    end

    parameters = []
    paramfile_params.merge(paramoption_params).each do |name, value|
      parameters << {"name" => name, "value" => value}
    end

    return parameters
  end
  
  def get_error_message_context(message)
    if message.start_with? "Undefined parameter"
      return "Use -p, --parameter NAME=VALUE to set parameter NAME to value VALUE."
    end
    return ""
  end
  
protected

  def self.inherited(klass)
    unless klass == Mortar::Command::Base
      help = extract_help_from_caller(caller.first)

      Mortar::Command.register_namespace(
        :name => klass.namespace,
        :description => help.first
      )
    end
  end

  def self.method_added(method)
    return if self == Mortar::Command::Base
    return if private_method_defined?(method)
    return if protected_method_defined?(method)

    help = extract_help_from_caller(caller.first)
    resolved_method = (method.to_s == "index") ? nil : method.to_s
    command = [ self.namespace, resolved_method ].compact.join(":")
    banner = extract_banner(help) || command

    Mortar::Command.register_command(
      :klass       => self,
      :method      => method,
      :namespace   => self.namespace,
      :command     => command,
      :banner      => banner.strip,
      :help        => help.join("\n"),
      :summary     => extract_summary(help),
      :description => extract_description(help),
      :options     => extract_options(help)
    )
  end

  def self.alias_command(new, old)
    raise "no such command: #{old}" unless Mortar::Command.commands[old]
    Mortar::Command.command_aliases[new] = old
  end

  #
  # Parse the caller format and identify the file and line number as identified
  # in : http://www.ruby-doc.org/core/classes/Kernel.html#M001397.  This will
  # look for a colon followed by a digit as the delimiter.  The biggest
  # complication is windows paths, which have a color after the drive letter.
  # This regex will match paths as anything from the beginning to a colon
  # directly followed by a number (the line number).
  #
  # Examples of the caller format :
  # * c:/Ruby192/lib/.../lib/mortar/command/addons.rb:8:in `<module:Command>'
  # * c:/Ruby192/lib/.../mortar-2.0.1/lib/mortar/command/pg.rb:96:in `<class:Pg>'
  # * /Users/ph7/...../xray-1.1/lib/xray/thread_dump_signal_handler.rb:9
  #
  def self.extract_help_from_caller(line)
    # pull out of the caller the information for the file path and line number
    if line =~ /^(.+?):(\d+)/
      extract_help($1, $2)
    else
      raise("unable to extract help from caller: #{line}")
    end
  end

  def self.extract_help(file, line_number)
    buffer = []
    lines = Mortar::Command.files[file]

    (line_number.to_i-2).downto(0) do |i|
      line = lines[i]
      case line[0..0]
        when ""
        when "#"
          buffer.unshift(line[1..-1])
        else
          break
      end
    end

    buffer
  end

  def self.extract_banner(help)
    help.first
  end

  def self.extract_summary(help)
    extract_description(help).split("\n")[2].to_s.split("\n").first
  end

  def self.extract_description(help)
    help.reject do |line|
      line =~ /^\s+-(.+)#(.+)/
    end.join("\n")
  end

  def self.extract_options(help)
    help.select do |line|
      line =~ /^\s+-(.+)#(.+)/
    end.inject({}) do |hash, line|
      description = line.split("#", 2).last
      long  = line.match(/--([0-9A-Za-z\- ]+)/)[1].strip
      short = line.match(/-([0-9A-Za-z ])[ ,]/) && $1 && $1.strip
      hash.update(long.split(" ").first => { :desc => description, :short => short, :long => long })
    end
  end

  def current_command
    Mortar::Command.current_command
  end

  def extract_option(key)
    options[key.dup.gsub('-','').to_sym]
  end

  def invalid_arguments
    Mortar::Command.invalid_arguments
  end

  def shift_argument
    Mortar::Command.shift_argument
  end

  def get_remaining_arguments_as_string
    Mortar::Command.get_remaining_arguments_as_string
  end

  def validate_arguments!
    Mortar::Command.validate_arguments!
  end

  def validate_git_based_project!
    unless project.root_path
      error("#{current_command[:command]} must be run from the checked-out project directory")
    end
    
    unless project.remote
      error("Unable to find git remote for project #{project.name}")
    end
  end

  def validate_script!(script_name)
    pigscript = project.pigscripts[script_name]
    controlscript = project.controlscripts[script_name]
    unless pigscript || controlscript
      available_pigscripts = project.pigscripts.none? ? "No pigscripts found" : "Available pigscripts:\n#{project.pigscripts.keys.sort.join("\n")}"
      available_controlscripts = project.controlscripts.none? ? "No controlscripts found" : "Available controlscripts:\n#{project.controlscripts.keys.sort.join("\n")}"
      error("Unable to find a pigscript or controlscript for #{script_name}\n\n#{available_pigscripts}\n\n#{available_controlscripts}")
    end

    if pigscript && controlscript
      error("Naming conflict.  #{script_name} refers to both a pigscript and a controlscript.  Please rename scripts to avoid conflicts.")
    end

    pigscript or controlscript
  end
  
  def validate_pigscript!(pigscript_name)
    unless pigscript = project.pigscripts[pigscript_name]
      available_scripts = project.pigscripts.none? ? "No pigscripts found" : "Available scripts:\n#{project.pigscripts.keys.sort.join("\n")}"
      error("Unable to find pigscript #{pigscript_name}\n#{available_scripts}")
    end
    pigscript
  end

  def extract_project_in_dir_no_git()
    current_dirs = Dir.glob("*/")
    missing_dir = Mortar::Project::Project.required_directories.find do |required_dir|
      ! current_dirs.include?("#{required_dir}/")
    end
    
    return missing_dir ? nil : [File.basename(Dir.getwd), nil]
  end

  def extract_project_in_dir(project_name=nil)
    # returns [project_name, remote_name]
    # TODO refactor this very messy method
    # when we have a more full sense of which options are supported when
    return unless git.has_dot_git?
    
    remotes = git.remotes(git_organization)
    return if remotes.empty?

    if remote = options[:remote]
      # extract the project whose remote was provided
      [remotes[remote], remote]
    elsif remote = extract_project_from_git_config
      # extract the project setup in git config
      [remotes[remote], remote]
    else
      if project_name
        # search for project by name
        if project_remote = remotes.find {|r_name, p_name| p_name == project_name}
          [project_name, project_remote.first[0]]
        else
          [project_name, nil]
        end
      elsif remotes.values.uniq.size == 1
        # take the only project in the remotes
        [remotes.first[1], remotes.first[0]]
      else
        raise(Mortar::Command::CommandFailed, "Multiple projects in folder and no project specified.\nSpecify which project to use with --project <project name>")
      end
    end
  end

  def extract_project_from_git_config
    remote = git.git("config mortar.remote", false)
    remote == "" ? nil : remote
  end

  def git_organization
    ENV['MORTAR_ORGANIZATION'] || default_git_organization
  end

  def default_git_organization
    "mortarcode"
  end
  
  def polling_interval
    (options[:polling_interval] || 2.0).to_f
  end

  def no_browser?
    (options[:no_browser])
  end

end

module Mortar::Command
  unless const_defined?(:BaseWithApp)
    BaseWithApp = Base
  end
end
