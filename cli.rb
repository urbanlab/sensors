#!/usr/bin/env ruby
$:.unshift(File.dirname(__FILE__) + '/') unless $:.include?(File.dirname(__FILE__) + '/')

require 'rubygems'
require 'shell'

Bombshell.launch(Redis_client::Shell)

