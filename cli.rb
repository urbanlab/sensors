#!/usr/bin/env ruby
$:.unshift(File.dirname(__FILE__) + '/') unless $:.include?(File.dirname(__FILE__) + '/')


##### Saving utilities #####
	
def redis_to_json
	require './redis-interface.rb'
	require 'json'
	r = Redis_interface.new 1
	config = {}
	config["profile"] = {:sensor => r.list_profiles(:sensor), :actuator => r.list_profiles(:actuator)}
	config["multiplexers"] = r.list_multis
	config["multiplexers"].each_key do |id|
		config["multiplexers"][id][:sensors] = r.list(:sensor, id)
		config["multiplexers"][id][:actuators] = r.list(:actuator, id)
		config["multiplexers"][id].delete(:supported) #regenerate at launch
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
	require './redis-interface.rb'
	r = Redis_interface.new 1
	redis = Redis.new
	input = ARGF.read
	config = JSON.parse(input)
	
	# JSON transforme les symboles et int en string pour les clefs...
	config.symbolize_keys!
	config[:profile].symbolize_keys!
	config[:profile].each do |type, configs|
		configs.each do |name, profile|
			profile.symbolize_keys!
		end
	end
	config[:multiplexers].integerize_keys!
	config[:multiplexers].each do |id, config|
		config.symbolize_keys!
		config[:sensors].integerize_keys!
		config[:actuators].integerize_keys!
		config[:sensors].each do |name, config|
			config.symbolize_keys!
		end
		config[:actuators].each do |name, config|
			config.symbolize_keys!
		end
	end

	# Reconstitution
	config[:profile][:sensor].each do |name, profile|
		r.add_profile({:type => :sensor, :name => name}.merge(profile))
	end
	config[:profile][:actuator].each do |name, profile|
		r.add_profile({:type => :actuator, :name => name}.merge(profile))
	end
	config[:multiplexers].each do |multi_id, multi_config|
		r.set_multi_config(multi_id.to_i, multi_config["description"])
		multi_config[:sensors].each do |sens_id, sens_config|
			r.add(:sensor, multi_id.to_i, sens_config.merge({pin: sens_id.to_i}))
		end
		multi_config[:actuators].each do |actu_id, actu_config|
			r.add(:actuator, multi_id.to_i, actu_config.merge({pin: actu_id.to_i}))
		end
	end
	
	#redis.publish("config", input)
end


