#!/usr/bin/env ruby
$:.unshift(File.dirname(__FILE__) + '/') unless $:.include?(File.dirname(__FILE__) + '/')
require 'optparse'
require 'extensions'

##### Saving utilities #####
# TODO network avec -i
def redis_to_json
	require './redis-interface-client.rb'
	require 'json'
	r = Redis_interface_client.new @network
	config = {}
	config["profile"] = {:sensor => r.list_profiles(:sensor), :actuator => r.list_profiles(:actuator)}
	config["multiplexer"] = r.list_multis
	config["multiplexer"].each_key do |id|
		config["multiplexer"][id][:sensor] = r.list(:sensor, id)
		config["multiplexer"][id][:actuator] = r.list(:actuator, id)
		config["multiplexer"][id].delete(:state)
		config["multiplexer"][id].delete(:supported) #regenerate at launch
	end
	
	JSON.pretty_generate(config)
end

def profiles_to_json
	require 'redis-interface-client'
	require 'json'
	r = Redis_interface_client.new @network
	config = {}
	config["profile"] = {sensor: r.list_profiles(:sensor), actuator: r.list_profiles(:actuator)}
	JSON.pretty_generate(config)
end

def load_from_file file
	require 'redis-interface-client'
	require 'json'
	r = Redis_interface_client.new @network
	conf_json = file.read
	config = JSON.parse(conf_json)
	# JSON ne garde pas les types de clefs, ni la difference entre string et symbol pour les valeurs
	config.symbolize_keys!
	if config[:profile]
		config[:profile].symbolize_keys!
		config[:profile].each do |type, profiles|
			profiles.each do |name, profile|
				profile.symbolize_keys!
				r.add_profile(type, name, profile)
			end
		end
	end
	if config[:multiplexer]
		config[:multiplexer].integerize_keys!
		config[:multiplexer].each do |multi_id, config|
			config.symbolize_keys!
			r.set_description(multi_id, config.delete(:description))
			config.each do |type, device_configs|
				device_configs.integerize_keys!
				device_configs.each do |device_id, device_config|
					device_config.symbolize_keys!
					device_config[:pin] = device_id
					r.add(type, multi_id, device_config)
				end
			end
		end
	end
end

options = {}
opts = OptionParser.new do |opts|
	opts.banner = "Usage: cli.rb [options] network"

	opts.on_tail("-i", "--interactive", "Launch interactive shell") do
		require 'rubygems'
		require 'shell'
		require 'yard'
		Bombshell.launch(Redis_client::Shell) if ARGV.size == 0
		exit
	end
	
	opts.on("-s", "--save-configuration FILE", "Save the whole configuration to FILE") do |file|
		f = File.new(file, "w")
		f << redis_to_json
		f.close
		exit
	end
		
	opts.on("-p", "--save-profiles FILE", "Save all the profiles to FILE") do |file|
		f = File.new(file, "w")
		f << profiles_to_json
		f.close
		exit
	end
	
	opts.on("-l", "--load-configuration FILE", "Load a configuration from FILE") do |file|
		f = File.new(file, "r")
		load_from_file(f)
		f.close
		exit
	end
	
	opts.on_tail("-d", "--delete-multiplexers", "Deletes all the multiplexers' configuration registered") do
		puts "Not implemented yet"
		exit
	end
	
	opts.on_tail("-D", "--delete-all", "Deletes everything, even the profiles") do
		puts "Not implemented yet"
		exit
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		puts "Each option is exclusive"
		exit
	end
end

if ARGV.size == 0
	puts opts
	puts "Each option is exclusive"
	exit
end

network = ARGV.pop
if network.is_integer?
	@network = network.to_i
	opts.parse!
	load_from_file STDIN
else
	puts opts
	puts "Each option is exclusive"
	exit
end



