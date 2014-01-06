#
# Copyright 2010, Opscode, Inc.
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

require 'sinatra/base'
require 'chef'
require 'chef/node'
require 'chef/mixin/xml_escape'
require 'chef/rest'
require 'JSON'

class ChefRundeck < Sinatra::Base

  include Chef::Mixin::XMLEscape

  class << self
    attr_accessor :config_file
    attr_accessor :username
    attr_accessor :api_url
    attr_accessor :web_ui_url
    attr_accessor :client_key

    def configure
      Chef::Config.from_file(ChefRundeck.config_file)
      Chef::Log.level = Chef::Config[:log_level]

      unless ChefRundeck.api_url
        ChefRundeck.api_url = Chef::Config[:chef_server_url]
      end

      unless ChefRundeck.client_key
        ChefRundeck.client_key = Chef::Config[:client_key]
      end
    end
  end

  get '/' do
    content_type 'text/xml'
    response = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE project PUBLIC "-//DTO Labs Inc.//DTD Resources Document 1.0//EN" "project.dtd"><project>'
    rest = Chef::REST.new(ChefRundeck.api_url)
    nodes = rest.get_rest("/nodes/")    

    rundeckNodes = {}
    nodes.keys.each do |node_name|
      node = rest.get_rest("/nodes/#{node_name}")
      #--
      # Certain features in Rundeck require the osFamily value to be set to 'unix' to work appropriately. - SRK
      #++
      begin 
        rundeckNode = RundeckNode.new

        rundeckNode.description = node_name
        rundeckNode.nodename = node_name

        if(!node.has_key?("automatic"))
          next
        end
        rundeckNode.osArch = node['automatic']['kernel']['machine']
        rundeckNode.osFamily = node['automatic']['platform']
        rundeckNode.osVersion = node['automatic']['platform_version']

        if(node['automatic'].has_key?("kernel"))
          rundeckNode.osFamily = node['automatic']['kernel']['os'] =~ /windows/i ? 'windows' : 'unix'
        else
          rundeckNode.osFamily = "unknown"
        end

        if(!node['automatic'].has_key?('fqdn'))
          rundeckNode.hostname = node['automatic']['hostname']
        else
          rundeckNode.hostname = node['automatic']['fqdn']
        end

        node['automatic']['recipes'].each do |recipe|
          rundeckNode.add_tag("recipe[" + recipe + "]")
        end
        node['automatic']['roles'].each do |role|
          rundeckNode.add_tag("role[" + role + "]")
        end
        node['normal']['tags'].each do |tag|
          rundeckNode.add_tag(tag)
        end

        rundeckNode.username = ChefRundeck.username
        rundeckNode.editUrl = "#{ChefRundeck.web_ui_url}/nodes/#{node_name}/edit"
        rundeckNodes[node_name] = rundeckNode



      rescue Exception => ex
        puts ex.message
        puts ex.backtrace.join("\n")
        puts JSON.dump(node)
      end
    end
    rundeckNodes.to_yaml
  end
end

class RundeckNode
  attr_accessor :nodename
  attr_accessor :type
  attr_accessor :description
  attr_accessor :osArch
  attr_accessor :osName
  attr_accessor :osVersion
  attr_accessor :osFamily
  attr_accessor :username
  attr_accessor :editUrl
  attr_reader   :hostname

  def initialize
  end

  def hostname=(hostname)
    if hostname =~ /\.bluestatedigital.com/ && hostname !~ /\.colo\.bluestatedigital\.com/
      hostname = hostname.sub(/\.bluestatedigital\.com/, ".colo.bluestatedigital.com")
    end
    @hostname = hostname
  end

  def tags
    @tags.join(',')
  end
  def tags=(tags)
    @tags = tags
  end
  def add_tag(tag)
    if(!@tags)
      @tags = []
    end
    @tags.push(tag)
  end
end
