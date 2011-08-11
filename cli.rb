#!/usr/bin/env ruby
$:.unshift(File.dirname(__FILE__) + '/') unless $:.include?(File.dirname(__FILE__) + '/')
require 'optparse'
require 'extensions'
require 'pp'

##### Saving utilities #####
# TODO network avec -i
def redis_to_json
	require './redis-interface-client.rb'
	require 'json'
	r = Redis_interface_client.new $network, $r_options[:redis_host], $r_options[:redis_port]
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
	r = Redis_interface_client.new $network
	config = {}
	config["profile"] = {sensor: r.list_profiles(:sensor), actuator: r.list_profiles(:actuator)}
	JSON.pretty_generate(config)
end

def load_from_file file
	require 'redis-interface-client'
	require 'json'
	r = Redis_interface_client.new $network, $r_options[:redis_host], $r_options[:redis_port]
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
			config.select{|k,v| k == :sensor or k == :actuator}.each do |type, device_configs|
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
$r_options = {}
opts = OptionParser.new do |opts|
	opts.banner = "Usage: cli.rb [options] network"

	opts.on("-i", "--interactive", "Launch interactive shell") do
		options[:interactive] = true
	end

	$r_options[:redis_host] = 'localhost'
	opts.on("-H", "--redis-host HOST", "Define redis host you want to connect to") do |host|
		$r_options[:redis_host] = host
	end
	
	$r_options[:redis_port] = 6379
	opts.on("-P", "--redis-port PORT", Integer, "Define port where redis is listening to") do |port|
		$r_options[:redis_port] = port
	end
	
	opts.on("-s", "--save-configuration FILE", "Save the whole configuration to FILE") do |file|
		options[:save_all] = file
	end
		
	opts.on("-p", "--save-profiles FILE", "Save all the profiles to FILE") do |file|
		options[:save_profiles] = file
	end
	
	opts.on("-l", "--load-configuration FILE", "Load a configuration from FILE") do |file|
		options[:load] = file
	end
	
	opts.on("-d", "--delete-multiplexers", "Deletes all the multiplexers' configuration registered") do
		options[:delete_multiplexers] = true
	end
	
	opts.on_tail("-D", "--delete-all", "Deletes everything, even the profiles") do
		options[:delete_all] = true
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end

if ARGV.size == 0
	puts opts
	exit
end

network = ARGV.pop
if network.is_integer?
	$network = network.to_i
	opts.parse!
	
	if options[:load]
		f = File.new(options[:load], "r")
		load_from_file f
		f.close
	end
	if options[:delete_multiplexers]
		puts "Deleting multiplexers not implemented yet"
	end
	if options[:delete_all]
		puts "Deleting all not implemented yet"
	end
	if options[:save_profiles]
		f = File.new(options[:save_profiles], "w")
		f << profiles_to_json
		f.close
	end
	if options[:save_all]
		f = File.new(options[:save_all], "w")
		f << redis_to_json
		f.close
	end
	if options[:interactive]
		require 'rubygems'
		require 'shell'
		require 'yard'
		Bombshell.launch(Redis_client::Shell)
		exit
	end
	if options.empty?
		load_from_file STDIN
	end
else
	puts opts
	exit
end



