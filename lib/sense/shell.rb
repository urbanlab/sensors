require 'bombshell'
require 'sense/client'
require 'yard'

module Sense
	# Interactive shell
	class Shell < Bombshell::Environment
		include Bombshell::Shell

		prompt_with "sense@#{$r_options[:redis_host]}:#{$network}"
		
		before_launch do |arg|
			$redis = Sense::Client.new $network, $r_options[:redis_host], $r_options[:redis_port]
			puts "Connected to #{$r_options[:redis_host]}:#{$r_options[:redis_port]} on network #{$network}."
		end
		
		# Print the list of multiplexers on my network
		#
		def list_multis #TODO limiter accès redis
			$redis.list_multis.sort.each do |multi, config|
				supported = $redis.support(config[:supported])
				#online = config[:state] ? "ON" : "OFF"
				puts "#{multi} : #{config[:description]} (supports : #{supported.join(", ")})"
			end
		end
		
		# Switch network
		#
		def switch_network network
			if network.is_a? Integer
				$network = network
				$redis = Sense::Client.new $network, $r_options[:redis_host], $r_options[:redis_port]
			else
				puts "network must be an integer"
			end
		end
		
		# Print the list of all the multiplexers
		#
		def list_all_multis
			$redis.list_multis('*').sort.each do |multi, config|
				supported = $redis.support(config[:supported])
				puts "#{multi} (network #{config[:network]}) (supports : #{supported.join(", ")})"
			end
		end
		
		# Print the list of multiplexers that don't have any task running
		#
		def list_unconfigured
			$redis.list_multis(0).each do |multi, config|
				supported = $redis.support(config[:supported])
				online = config[:state] ? "ON" : "OFF"
				puts "#{multi} (#{online}): #{config[:description]} (supports : #{supported.join(", ")})"
			end
		end
		
		# Associate a multiplexer to the network
		# @param (see Sense::Client#take)
		#
		def take multi_id
			success, message = $redis.take multi_id
			puts success ? "OK" : "KO : #{message}"
		end
		
		# Add a sensor to a multiplexer
		# @param [Integer] multi Id of the multiplexer
		# @param [Integer] pin Pin where the device is plugged
		# @param [String] name Name given to the sensor
		# @param [String] profile Name of the profile of the device
		# @param [Integer] period duration between 2 check, in milliseconds
		# @param [Hash] args optionnal additionnal informations
		#
		def add_sensor(multi, pin, name, profile, period = nil, args = {})
			args.merge!({multi: multi, name: name, profile: profile, pin: pin})
			args[:period] = period if period
			success, message = $redis.add :sensor, args.delete(:multi), args
			puts success ? "OK" : "KO : #{message}"
		end
		
		# Add an actuator to a multiplexer
		# @param (see Sense::Shell#add_sensor)
		def add_actuator(multi, pin, name, profile, period = nil, args = {})
			args.merge!({multi: multi, pin: pin, name: name, profile: profile})
			args[:period] = period if period
			success, message = $redis.add :actuator, args.delete(:multi), args
			puts success ? "OK" : "KO : #{message}"
		end
		
		# Turn on an actuator of a multi
		# @param [Integer] multi Id of the multi where the actuator is plugged
		# @param [Integer] pin Pin of the actuator
		#
		def switch_on(multi, pin)
			success, message = $redis.set_actuator_state(multi, pin, 1)
			puts success ? "OK" : "KO : #{message}"
		end
		
		# Turn off an actuator of a multi
		# @param (see Sense::Shell#switch_on)
		#
		def switch_off(multi, pin)
			success, message = $redis.set_actuator_state(multi, pin, 0)
			puts success ? "OK" : "KO : #{message}"
		end
		
		# Modify the description of a multi
		# @param [Integer] multi Id of the multiplexer you want to modify
		# @param [String] description The new description
		#
		def set_description(multi, description)
			multi = $redis.get_multi_id(multi)
			if $redis.set_description(multi, description)
				puts "OK"
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		# Remove a sensor from a multi
		# @param [Integer] multi Id of the multiplexer
		# @param [Integer] pin Pin where the sensor was plugged
		#
		def remove_sensor(multi, pin)
			success, message = $redis.remove :sensor, multi, pin
			puts success ? "OK" : "KO : #{message}"
		end
		
		# Remove an actuator from a multi
		# @param (see Sense::Shell#remove_sensor)
		#
		def remove_actuator(multi, pin)
			success, message = $redis.remove :actuator, multi, pin
			puts success ? "OK" : "KO : #{message}"
		end
		
		# List the sensors and actuators of a multiplexer
		# @param [Integer] multi Id of the multiplexer
		#
		def list_devices(multi)
			multi = $redis.get_multi_id multi
			if $redis.knows_multi? multi
				puts "===  Sensors  ==="
				$redis.list(:sensor, multi).sort.each do |pin, conf|
					s = "#{pin} : #{conf[:name]} #{conf[:profile]}"
					s << " - Period : #{conf[:period]}" if conf[:period]
					puts s
				end
				puts "=== Actuators ==="
				$redis.list(:actuator, multi).sort.each do |pin, conf|
					s = "#{pin} : #{conf[:name]} #{conf[:profile]}"
					s << " - Period : #{conf[:period]}" if conf[:period]
					puts s
				end
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		# Add a new sensor profile
		# @param name (see Sense::Client#add_profile)
		# @option (see Sense::Client#add_profile)
		#
		def add_sensor_profile(name, profile={})
			begin
				$redis.add_profile :sensor, name, profile
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		# Add a new actuator profile
		# @param name (see Sense::Client#add_profile)
		# @option (see Sense::Client#add_profile)
		#
		def add_actuator_profile(name, profile={})
			begin
				$redis.add_profile :actuator, name, profile
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		# List the registered sensor profiles
		#
		def list_sensor_profiles
			$redis.list_profiles(:sensor).each do |name, profile|
				s = "* #{name} :\nFunction : #{profile[:function]}\nUnit: #{profile[:unit]}"
				s << "\nPeriod : #{profile[:period]}" if profile[:period]
				s << "\nRPN : #{profile[:rpn]}" if profile[:rpn]
				s << "\nPrecision : #{profile[:precision]}" if profile[:precision]
				s << "\n\n"
				puts s
			end
		end
		
		# List the registered actuator profiles
		#
		def list_actuator_profiles
			$redis.list_profiles(:actuator).each do |name, profile|
				s = "* #{name} :\nFunction : #{profile[:function]}"
				s << "\nPeriod : #{profile[:period]}" if profile[:period]
				s << "\n\n"
				puts s
			end
		end
		
		# Remove a sensor profile
		# @param [String] name Name of the profile
		#
		def remove_sensor_profile name
			puts $redis.remove_profile(:sensor, name) ? "OK" : "KO"
		end
		
		# Remove an actuator profile
		# @param [String] name Name of the profile
		#
		def remove_actuator_profile name
			puts $redis.remove_profile(:actuator, name) ? "OK" : "KO"
		end
		
		# Read a value from a sensor
		# @param [Integer] multi Id of the multiplexer where the sensor is plugged
		# @param [Integer] pin Pin of the sensor
		def get_sensor_value multi, pin
			multi = $redis.get_multi_id multi
			pin = $redis.get_pin :sensor, multi, pin
			hash = $redis.get_sensor_value(multi, pin)
			puts "#{hash[:name]} : #{hash[:value]}#{hash[:unit]} (this information is #{(Time.now - Time.at(hash[:timestamp])).round(1)}s old)"
		end
		
		# Get some help
		# @param [String, Symbol] function Function to describe
		#
		def help function = nil
			YARD::Registry.load!
			if function
				description = describe function
				if not description
					puts "Unknown function."
					return
				else
					puts description
				end
			else
				puts "Type help :<the function>. Like, help :switch_on"
			end
		end
		
		private
		
		# Produce readable description of a function from YARD registry
		#
		def describe function
			doc = YARD::Registry["#{self.class}##{function}"]
			return nil unless doc
			descr = "\n#{doc.name(true)}(#{doc.tags(:param).inject([]){|a,p| a.push(p.name)}.join(" ")}) : #{doc.docstring}\n\n"
			if doc.has_tag?(:param)
				descr << "Parameters :\n"
				doc.tags(:param).each do |parameter|
					descr << "(#{parameter.types.join(", ")}) #{parameter.name} - #{parameter.text}\n"
				end
				descr << "\n"
			end
			if doc.has_tag?(:option)
				options = doc.tags(:option)
				descr << "Customizable Hash of options \"#{options[0].name}\"\n"
				options.each do |option|
					descr << "(#{option.pair.types.join(", ")}) #{option.pair.name} - #{option.pair.text}\n"
				end
				descr << "\n"
			end
			descr << "\n"
		end
	end
end

