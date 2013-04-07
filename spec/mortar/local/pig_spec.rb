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
require 'mortar/local/pig'
require 'launchy'


class Mortar::Local::Pig
  attr_reader :command
end


module Mortar::Local
  describe Pig do

    context("install") do

      it "handles necessary installation steps" do
        # creates the parent directory, downloads the tgz, extracts it,
        # chmods bin/pig, removes tgz, and notes the installation
        FakeFS do
          pig = Mortar::Local::Pig.new
          local_pig_archive = File.join(pig.local_install_directory, pig.pig_archive_file)
          mock(pig).download_file(pig.pig_archive_url, pig.local_install_directory) do
            # Simulate the tgz file being downloaded, this should be deleted
            # before the method finishes executing
            FileUtils.touch(local_pig_archive)
          end
          mock(pig).extract_tgz(local_pig_archive, pig.local_install_directory)
          mock(pig).note_install("pig")
          begin
            previous_stdout, $stdout = $stdout, StringIO.new
            pig.install
          ensure
            $stdout = previous_stdout
          end
          expect(File.exists?(local_pig_archive)).to be_false
        end
      end

    end

    context "install_or_update" do

      it "does nothing if existing install and no update available" do
        pig = Mortar::Local::Pig.new
        mock(pig).should_do_pig_install?.returns(false)
        mock(pig).should_do_pig_update?.returns(false)
        FakeFS do
          FileUtils.mkdir_p(File.dirname(pig.local_install_directory))
          FileUtils.rm_rf(pig.local_install_directory, :force => true)
          pig.install_or_update
          expect(File.exists?(pig.local_install_directory)).to be_false
        end
      end

      it "does install if none has been done before" do
        pig = Mortar::Local::Pig.new
        mock(pig).should_do_pig_install?.returns(true)
        mock(pig).install
        capture_stdout do
          pig.install_or_update
        end
      end

      it "does install if one was done before but there is an update" do
        pig = Mortar::Local::Pig.new
        mock(pig).should_do_pig_install?.returns(false)
        mock(pig).should_do_pig_update?.returns(true)
        mock(pig).install
        capture_stdout do
          pig.install_or_update
        end
      end

    end


    context "show_illustrate_output" do

      it "takes a path to a json file, renders the html template, and opens it" do
        fake_illustrate_data = {
          "tables" => [
            {
              "Op" => "LOStore",
              "alias" => "some_relation",
              "notices" => ["things are fouled up", "no just kidding, it's fine"],
              "fields" => ["person_id", "first_name", "last_name"],
              "data" => [
                ["1", "mike", "jones"],
                ["2", "cleopatra", "jones"],
                ["3", "john paul", "jones"],
              ],
            },
          ],
          "udf_output" => "hey, I'm a udf",
        }
        pig = Mortar::Local::Pig.new
        template_location = pig.resource_locations["illustrate_template"]
        template_contents = File.read(template_location)
        output_path = pig.resource_destinations["illustrate_html"]
        mock(pig).decode_illustrate_input_file("foo/bar/file.json").returns(fake_illustrate_data)

        # TODO: test that these files are copied
        ["illustrate_css", 
         "jquery", "jquery_transit", "jquery_stylestack", 
         "mortar_table", "zeroclipboard", "zeroclipboard_swf"].each { |resource|
          mock(pig).copy_if_not_present_at_dest.with(
            File.expand_path(pig.resource_locations[resource]),
            pig.resource_destinations[resource]
          ).returns(nil)
        }

        mock(Launchy).open(File.expand_path(output_path))
        FakeFS do
          FileUtils.mkdir_p(File.dirname(template_location))
          File.open(template_location, 'w') { |f| f.write(template_contents) }
          begin
            previous_stdout, $stdout = $stdout, StringIO.new
            pig.show_illustrate_output("foo/bar/file.json")
          ensure
            $stdout = previous_stdout
          end
          expect(File.exists?(output_path)).to be_true
        end
      end

    end

    context "decode_illustrate_input_file" do

      it "decodes the contents of the file" do
        json = %{[{"alias": "some_relation", "Op": "LOStore"}]}
        expected_data = [ {
            "Op" => "LOStore",
            "alias" => "some_relation",
          }
        ]
        pig = Mortar::Local::Pig.new
        illustrate_output_file = 'illustrate-output.json'
        FakeFS do
          File.open(illustrate_output_file, 'w') { |f| f.write(json) }
          actual_data = pig.decode_illustrate_input_file(illustrate_output_file)
          expect(actual_data).to eq(expected_data)
        end
      end

      it "handles invalid unicode characters" do
        json = %{{"tables": [ "hi \255"], "udf_output": [ ]}}
        expected_data = {
          'tables' => ['hi '],
          'udf_output' => [],
        }
        pig = Mortar::Local::Pig.new
        illustrate_output_file = 'illustrate-output.json'
        FakeFS do
          File.open(illustrate_output_file, 'w') { |f| f.write(json) }
          actual_data = pig.decode_illustrate_input_file(illustrate_output_file)
          expect(actual_data).to eq(expected_data)
        end
      end

    end

    context "illustrate_alias" do

      it "displays html results if illustrate was successful" do
        any_instance_of(Mortar::Project::PigScripts, :elements => nil, :path => "/foo/bar/baz.pig")
        script = Mortar::Project::PigScripts.new('/foo/bar/baz.pig', 'baz', 'pig')
        pig = Mortar::Local::Pig.new
        mock(pig).run_pig_command.with_any_args.returns(true)
        mock(pig).show_illustrate_output.with_any_args
        stub(pig).make_pig_param_file.returns('param.file')
        pig.illustrate_alias(script, 'my_alias', false, [])
      end

      it "skips results if illustrate was unsuccessful" do
        any_instance_of(Mortar::Project::PigScripts, :elements => nil, :path => "/foo/bar/baz.pig")
        script = Mortar::Project::PigScripts.new('/foo/bar/baz.pig', 'baz', 'pig')
        pig = Mortar::Local::Pig.new
        mock(pig).run_pig_command.with_any_args.returns(false)
        mock(pig).show_illustrate_output.with_any_args.never
        stub(pig).make_pig_param_file.returns('param.file')
        pig.illustrate_alias(script, 'my_alias', false, [])
      end

    end

  end
end
