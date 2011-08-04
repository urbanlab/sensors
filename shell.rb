require 'bombshell'
require 'redis-interface-client'
require 'yard'

# TODO document hash args
module Redis_client
	# Interactive shell
	class Shell < Bombshell::Environment
		include Bombshell::Shell

		prompt_with 'client'
		#@private
		def initialize argv
			super argv
			@redis = Redis_interface_client.new 1
		end
		
		# Print the list of multiplexers
		#
		def list_multi #TODO limiter accès redis
			@redis.list_multis.each do |multi, config|
				supported = @redis.support(config[:supported])
				puts "#{multi} : #{config[:description]} (supports : #{supported.join(", ")})"
			end
		end
		
		# Print the list of multiplexers that don't have any task running
		#
		def list_unconfigured
			@redis.list_multis.select {|multi, config| @redis.list(:sensor, multi).size + @redis.list(:actuator, multi).size == 0}.each do |multi, config|
				supported = @redis.support(config[:supported])
				puts "#{multi} : #{config[:description]} (supports : #{supported.join(", ")})"
			end
		end
		
		# Add a sensor to a multiplexer
		# @macro [new] device
		#  @param [Integer] multi Id of the multiplexer
		#  @param [Integer] pin Pin where the device is plugged
		#  @param [String] name Name given to the sensor
		#  @param [String] profile Name of the profile of the device
		#  @param [Integer] period duration between 2 check, in milliseconds
		#
		def add_sensor(multi, pin, name, profile, period = nil, args = {})
			begin
				args.merge!({multi: multi, pin: pin, name: name, profile: profile})
				args[:period] = period if period
				@redis.add :sensor, args.delete(:multi), args
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		# Add an actuator to a multiplexer
		# @macro device
		def add_actuator(multi, pin, name, profile, period = nil, args = {})
			begin
				args.merge!({multi: multi, pin: pin, name: name, profile: profile})
				args[:period] = period if period
				@redis.add :actuator, args.delete(:multi), args
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		# Turn on an actuator of a multi
		# @macro [new] actu
		#  @param [Integer] multi Id of the multi where the actuator is plugged
		#  @param [Integer] pin Pin of the actuator
		#
		def switch_on(multi, pin)
			@redis.set_actuator_state(multi, pin, 1)
		end
		
		# Turn off an actuator of a multi
		# @macro actu
		#
		def switch_off(multi, pin)
			@redis.set_actuator_state(multi, pin, 0)
		end
		
		# Modify the description of a multi
		# @param [Integer] multi Id of the multiplexer you want to modify
		# @param [String] description The new description
		#
		def set_description(multi, description)
			if @redis.set_description(multi, description)
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
			if @redis.remove :sensor, multi, pin
				puts "OK"
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		# Remove an actuator from a multi
		# @see #remove_sensor
		#
		def remove_actuator(multi, pin)
			if @redis.remove :actuator, multi, pin
				puts "OK"
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		# List the sensors of a multiplexer
		# @param [Integer] multi Id of the multiplexer
		#
		def list_sensors(multi)
			if (list = @redis.list(:sensor, multi))
				list.each do |k, v|
					puts "#{k} : #{v[:name]}, #{v[:profile]} (period : #{v[:period]})"
				end
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		# Add a new sensor profile
		# @option profile [String] :name Name of the profile
		# @option profile [String] :function Arduino function the profile uses
		# @option profile [String] :unit Unit of the value
		# @option profile [Integer, optional] :period default period
		# @option profile [Integer, optional] :option1 1st option (see arduino function)
		# @option profile [Integer, optional] :option2 2nd option (see arduino function)
		# @option profile [String, optional] :rpn RPN modification to apply to raw value
		# @option profile [Integer, optional] :precision Number of digit of the modified value (eg. +3+ for value like +334.411+, +-1+ for value like +330+)
		#
		def add_sensor_profile(profile={})
			profile[:type] = :sensor
			begin
				@redis.add_profile profile
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		# Add a new actuator profile
		#
		def add_actuator_profile(args={})
			args[:type] = :actuator
			begin
				@redis.add_profile args
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		# List the registered sensor profiles
		#
		def list_sensor_profiles
			@redis.list_profiles(:sensor).each do |name, profile|
				puts "#{name} : #{profile[:function]}, #{profile[:rpn]}, #{profile[:unit]}"
			end
		end
		
		# List the registered actuator profiles
		#
		def list_actuator_profiles
			@redis.list_profiles(:actuator).each do |name, profile|
				puts "#{name} : #{profile[:function]}"
			end
		end
		
		# Remove a sensor profile
		# @param [String] name Name of the profile
		#
		def remove_sensor_profile name
			puts @redis.remove_profile(:sensor, name) ? "OK" : "KO"
		end
		
		# Remove an actuator profile
		# @param [String] name Name of the profile
		#
		def remove_actuator_profile name
			puts @redis.remove_profile(:actuator, name) ? "OK" : "KO"
		end
		
		# Read a value from a sensor
		# @param [Integer] multi Id of the multiplexer where the sensor is plugged
		# @param [Integer] pin Pin of the sensor
		def get_sensor_value multi, pin
			config = @redis.get_config(:sensor, multi, pin)
			profile = @redis.get_profile(:sensor, config[:profile])
			profile[:precision] = profile[:precision] || 0
			value, timestamp = @redis.get_sensor_value(multi, pin)
			puts "#{value.round(profile[:precision])}#{profile[:unit]} (this information is #{(Time.now - Time.at(timestamp)).round(1)}s old)"
		end
		
		# Get some help
		# @param [String, Symbol] function Function to describe (or nil if you want all)
		#
		def help function = nil
			p 
			YARD::Registry.load!
			if function
				description = describe function
				if not description
					puts "Unknown function."
					return
				else
					puts description
				end
			end
		end
		
		private
		
		def describe function
			doc = YARD::Registry["#{self.class}##{function}"]
			return nil unless doc
			descr = "#{doc.name(true)} : #{doc.docstring}\n\n"
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

