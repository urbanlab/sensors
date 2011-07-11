#!/usr/bin/env ruby
$:.unshift(File.dirname(__FILE__) + '/') unless $:.include?(File.dirname(__FILE__) + '/')


##### Saving utilities #####
	
def redis_to_json
	require './redis-interface.rb'
	require 'json'
	r = Redis_interface.new 1
	config = {}
	config["profile"] = r.list_profiles
	config["multiplexers"] = r.list_multis
	config["multiplexers"].each_key do |id|
		config["multiplexers"][id]["sensors"] = r.list_sensors(id)
		config["multiplexers"][id].delete("supported") #regenerate at launch
	end
	
	JSON.pretty_generate(config)
end

if ARGV.size == 0
	require 'rubygems'
	require 'shell'
	Bombshell.launch(Redis_client::Shell) if ARGV.size == 0
elsif ARGV[0] && ARGV[0] == "-o"
	f = File.new(ARGV[1],"w")
	f << redis_to_json
	f.close
else
	require 'redis'
	redis = Redis.new
	input = ARGF.read
	redis.publish("config", input)
end



