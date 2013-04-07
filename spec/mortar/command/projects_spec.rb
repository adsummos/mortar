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

require 'spec_helper'
require 'fakefs/spec_helpers'
require 'mortar/command/projects'
require 'launchy'
require "mortar/api"


module Mortar::Command
  describe Projects do
    
    before(:each) do
      stub_core      
      @git = Mortar::Git::Git.new
    end

    before("create") do 
      @tmpdir = Dir.mktmpdir
      Dir.chdir(@tmpdir)
    end
    
    project1 = {'name' => "Project1",
                'status' => Mortar::API::Projects::STATUS_ACTIVE,
                'git_url' => "git@github.com:mortarcode-dev/Project1"}
    project2 = {'name' => "Project2",
                'status' => Mortar::API::Projects::STATUS_ACTIVE,
                'git_url' => "git@github.com:mortarcode-dev/Project2"}
        
    context("index") do
      
      it "shows appropriate message when user has no projects" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => []}))
        
        stderr, stdout = execute("projects")
        stdout.should == <<-STDOUT
You have no projects.
STDOUT
      end
      
      it "shows appropriate message when user has multiple projects" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
        
        stderr, stdout = execute("projects")
        stdout.should == <<-STDOUT
=== projects
Project1
Project2

STDOUT
      end
    end
    
    context("delete") do
      it "shows error message when user doesn't include project name" do
        stderr, stdout = execute("projects:delete")
        stderr.should == <<-STDERR
 !    Usage: mortar projects:delete PROJECTNAME
 !    Must specify PROJECTNAME.
STDERR
      end
      
      it "deletes project" do
        project_name = "COMMANDO"

        mock(Mortar::Auth.api).delete_project(project_name).returns(Excon::Response.new(:body => {}, :status => 200 )) 
        stderr, stdout = execute("projects:delete COMMANDO")
        stdout.should == <<-STDOUT
Sending request to delete project: COMMANDO... done

Your project has been deleted.
STDOUT
      end
      
    end
    
    context("create") do

      it "generates and registers a project" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
        project_id = "1234abcd1234abcd1234"
        project_name = "some_new_project"
        project_git_url = "git@github.com:mortarcode-dev/#{project_name}"
        mock(Mortar::Auth.api).post_project("some_new_project") {Excon::Response.new(:body => {"project_id" => project_id})}
        mock(Mortar::Auth.api).get_project(project_id).returns(Excon::Response.new(:body => {"status" => Mortar::API::Projects::STATUS_ACTIVE,
                                                                                             "git_url" => project_git_url})).ordered
        mock(@git).remotes.with_any_args.returns({})
        mock(@git).remote_add("mortar", project_git_url)

        # if the git stuff doesn't work, the registration will fail, so we can pretend it does work here
        mock(@git).git("add .").returns(true)
        mock(@git).git("commit -m \"Mortar project scaffolding\"").returns(true)
        mock(@git).push_master

        stderr, stdout = execute("projects:create #{project_name}", nil, @git)
        Dir.pwd.end_with?("some_new_project").should be_true
        File.exists?("macros").should be_true
        File.exists?("fixtures").should be_true
        File.exists?("pigscripts").should be_true
        File.exists?("udfs").should be_true
        File.exists?("README.md").should be_true
        File.exists?("Gemfile").should be_false
        File.exists?("macros/.gitkeep").should be_true
        File.exists?("fixtures/.gitkeep").should be_true
        File.exists?("pigscripts/some_new_project.pig").should be_true
        File.exists?("udfs/python/some_new_project.py").should be_true

        File.read("pigscripts/some_new_project.pig").each_line { |line| line.match(/<%.*%>/).should be_nil }

        stdout.should == <<-STDOUT
\e[1;32m      create\e[0m  
\e[1;32m      create\e[0m  README.md
\e[1;32m      create\e[0m  .gitignore
\e[1;32m      create\e[0m  pigscripts
\e[1;32m      create\e[0m  pigscripts/some_new_project.pig
\e[1;32m      create\e[0m  controlscripts
\e[1;32m      create\e[0m  controlscripts/.gitkeep
\e[1;32m      create\e[0m  macros
\e[1;32m      create\e[0m  macros/.gitkeep
\e[1;32m      create\e[0m  fixtures
\e[1;32m      create\e[0m  fixtures/.gitkeep
\e[1;32m      create\e[0m  udfs
\e[1;32m      create\e[0m  udfs/python
\e[1;32m      create\e[0m  udfs/python/some_new_project.py
Sending request to register project: some_new_project... done\n\n\r\e[0KStatus: ACTIVE  \n\nYour project is ready for use.  Type 'mortar help' to see the commands you can perform on the project.\n
STDOUT
      end

    end
    
    context("register") do
      
      it "show appropriate error message when user doesn't include project name" do
        stderr, stdout = execute("projects:register")
        stderr.should == <<-STDERR
 !    Usage: mortar projects:register PROJECT
 !    Must specify PROJECT.
STDERR
      end

      it "tells you to cd to the directory if one exists with the project name" do
        with_no_git_directory do
          # create the project, but a level down from current directory
          project_name = "existing_project_one_level_down"
          FileUtils.mkdir_p(File.join(Dir.pwd, project_name))
          stderr, stdout = execute("projects:register #{project_name}")
          stderr.should == <<-STDERR
 !    mortar projects:register must be run from within the project directory.
 !    Please "cd existing_project_one_level_down" and rerun this command.
STDERR
        end
      end

      it "tells you to create the git project in directory that doesn't have a git repository" do
        with_no_git_directory do
          stderr, stdout = execute("projects:register some_new_project")
          stderr.should == <<-STDERR
 !    No git repository found in the current directory.
 !    Please initialize a git repository for this project, and then rerun the register command.
 !    To initialize your project in git, use:
 !    
 !    git init
 !    git add .
 !    git commit -a -m "first commit"
STDERR
        end
      end

      it "errors when a project already exists with the name requested" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
        with_git_initialized_project do |p|           
          stderr, stdout = execute("projects:register Project1", nil, @git)
          stderr.should == <<-STDERR
 !    Your account already contains a project named Project1.
 !    Please choose a different name for your new project, or clone the existing Project1 code using:
 !    
 !    mortar projects:clone Project1
STDERR
        end
      end

      it "show appropriate error message when user tries to register a project inside of an existing project" do
         mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
         with_git_initialized_project do |p|           
           stderr, stdout = execute("projects:register some_new_project", nil, @git)
           stderr.should == <<-STDERR
 !    Currently in project: myproject.  You can not register a new project inside of an existing mortar project.
STDERR
         end
      end
      
      it "register a new project successfully - with status" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
        project_id = "1234abcd1234abcd1234"
        project_name = "some_new_project"
        project_git_url = "git@github.com:mortarcode-dev/#{project_name}"
        mock(Mortar::Auth.api).post_project("some_new_project") {Excon::Response.new(:body => {"project_id" => project_id})}
        mock(Mortar::Auth.api).get_project(project_id).returns(Excon::Response.new(:body => {"status" => Mortar::API::Projects::STATUS_PENDING})).ordered
        mock(Mortar::Auth.api).get_project(project_id).returns(Excon::Response.new(:body => {"status" => Mortar::API::Projects::STATUS_CREATING})).ordered
        mock(Mortar::Auth.api).get_project(project_id).returns(Excon::Response.new(:body => {"status" => Mortar::API::Projects::STATUS_ACTIVE,
                                                                                             "git_url" => project_git_url})).ordered
        
        mock(@git).has_dot_git?().returns(true)
        mock(@git).remotes.with_any_args.returns({})
        mock(@git).remote_add("mortar", project_git_url)
        mock(@git).push_master

        stderr, stdout = execute("projects:register #{project_name}  --polling_interval 0.05", nil, @git)
        stdout.should == <<-STDOUT
Sending request to register project: some_new_project... done\n\n\r\e[0KStatus: PENDING... /\r\e[0KStatus: CREATING... -\r\e[0KStatus: ACTIVE  \n\nYour project is ready for use.  Type 'mortar help' to see the commands you can perform on the project.\n
STDOUT
      end

      it "register a new project successfully - with status_code and status_description" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
        project_id = "1234abcd1234abcd1234"
        project_name = "some_new_project"
        project_git_url = "git@github.com:mortarcode-dev/#{project_name}"
        mock(Mortar::Auth.api).post_project("some_new_project") {Excon::Response.new(:body => {"project_id" => project_id})}
        mock(Mortar::Auth.api).get_project(project_id).returns(Excon::Response.new(:body => {"status_description" => "Pending", "status_code" => Mortar::API::Projects::STATUS_PENDING})).ordered
        mock(Mortar::Auth.api).get_project(project_id).returns(Excon::Response.new(:body => {"status_description" => "Creating", "status_code" => Mortar::API::Projects::STATUS_CREATING})).ordered
        mock(Mortar::Auth.api).get_project(project_id).returns(Excon::Response.new(:body => {"status_description" => "Active", "status_code" => Mortar::API::Projects::STATUS_ACTIVE,
                                                                                             "git_url" => project_git_url})).ordered

        mock(@git).has_dot_git?().returns(true)
        mock(@git).remotes.with_any_args.returns({})
        mock(@git).remote_add("mortar", project_git_url)
        mock(@git).push_master

        stderr, stdout = execute("projects:register #{project_name}  --polling_interval 0.05", nil, @git)
        stdout.should == <<-STDOUT
Sending request to register project: some_new_project... done\n\n\r\e[0KStatus: Pending... /\r\e[0KStatus: Creating... -\r\e[0KStatus: Active  \n\nYour project is ready for use.  Type 'mortar help' to see the commands you can perform on the project.\n
STDOUT
      end
      
    end

    context("set_remote") do
      
      it "sets the remote of a project" do
        with_git_initialized_project do |p|           
          project_name = p.name
          project_git_url = "git@github.com:mortarcode-dev/#{project_name}"
          `git remote rm mortar`
          mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [ { "name" => project_name, "status" => Mortar::API::Projects::STATUS_ACTIVE, "git_url" => project_git_url } ] })).ordered   

          mock(@git).remote_add("mortar", project_git_url)

          stderr, stdout = execute("projects:set_remote #{project_name}", p, @git)
          stdout.should == <<-STDOUT
Successfully added the mortar remote to the myproject project
STDOUT
        end
      end

      it "remote already added" do
        with_git_initialized_project do |p|           
          project_name = p.name

          stderr, stdout = execute("projects:set_remote #{project_name}", p, @git)
          stdout.should == <<-STDERR
The remote has already been set for project: myproject
STDERR
        end
      end

      it "No project given" do
        with_git_initialized_project do |p|           
          stderr, stdout = execute("projects:set_remote", p, @git)
          stderr.should == <<-STDERR
 !    Usage: mortar projects:set_remote PROJECT
 !    Must specify PROJECT.
STDERR
        end
      end

      it "No project with that name" do
        with_git_initialized_project do |p|           
          project_name = p.name
          project_git_url = "git@github.com:mortarcode-dev/#{project_name}"
          mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [ { "name" => "derp", "status" => Mortar::API::Projects::STATUS_ACTIVE, "git_url" => project_git_url } ] })).ordered   
          `git remote rm mortar`

          stderr, stdout = execute("projects:set_remote #{project_name}", p, @git)
          stderr.should == <<-STDERR
 !    No project named: myproject exists. You can create this project using:
 !    
 !     mortar projects:create
STDERR
        end
      end
    end
    
    
    context("clone") do
      
      it "shows appropriate error message when user doesn't include project name" do
        stderr, stdout = execute("projects:clone")
        stderr.should == <<-STDERR
 !    Usage: mortar projects:clone PROJECT
 !    Must specify PROJECT.
STDERR
      end
      
      it "shows appropriate error message when user tries to clone non-existent project" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
        
        stderr, stdout = execute('projects:clone sillyProjectName')
        stderr.should == <<-STDERR
 !    No project named: sillyProjectName exists.  Your valid projects are:
 !    Project1
 !    Project2
STDERR
      end
      
      it "shows appropriate error message when user tries to clone into existing directory" do
        with_no_git_directory do
          mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
          starting_dir = Dir.pwd
          project_dir = File.join(Dir.pwd, project1['name'])
          FileUtils.mkdir_p(project_dir)
          
          stderr, stdout = execute("projects:clone #{project1['name']}")
          stderr.should == <<-STDERR
 !    Can't clone project: #{project1['name']} since directory with that name already exists.
STDERR
        end
        
      end
      
      it "calls git clone when existing project is cloned" do
        mock(Mortar::Auth.api).get_projects().returns(Excon::Response.new(:body => {"projects" => [project1, project2]}))
        mock(@git).clone(project1['git_url'], project1['name'])
        
        stderr, stdout = execute('projects:clone Project1', nil, @git)
      end
      
    end
  end
end