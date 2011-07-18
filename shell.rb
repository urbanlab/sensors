require 'bombshell'
require 'redis-interface'

module Redis_client
	class Shell < Bombshell::Environment
		include Bombshell::Shell

		prompt_with 'client'
		def initialize argv
			super argv
			@redis = Redis_interface.new 1
		end
	
		def list_multi
			@redis.list_multis.each do |multi, config|
				supported = @redis.support(config[:supported])
				puts "#{multi} : #{config[:description]} (supports : #{supported.join(", ")})"
			end
		end
		
		def list_unconfigured
			@redis.list_multis.select {|multi, config| @redis.list(:sensor, multi).size + @redis.list(:actuator, multi).size == 0}.each do |multi, config|
				supported = @redis.support(config[:supported])
				puts "#{multi} : #{config[:description]} (supports : #{supported.join(", ")})"
			end
		end
		
		def add_sensor(multi, pin, name, profile, period = nil, args = {})
			begin
				args.merge!({multi: multi, pin: pin, name: name, profile: profile})
				args[:period] = period if period
				@redis.add :sensor, args.delete(:multi), args
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		def add_actuator(multi, pin, name, profile, period = nil, args = {})
			begin
				args.merge!({multi: multi, pin: pin, name: name, profile: profile})
				args[:period] = period if period
				@redis.add :actuator, args.delete(:multi), args
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		def switch_on(device, pin)
			@redis.set_actuator_state(device, pin, 1)
		end
		
		def switch_off(device, pin)
			@redis.set_actuator_state(device, pin, 0)
		end
		
		def set_description(device, description)
			if @redis.set_description(device, description)
				puts "OK"
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		def remove_sensor(device, pin)
			if @redis.remove :sensor, device, pin
				puts "OK"
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		def remove_actuator(device, pin)
			if @redis.remove :actuator, device, pin
				puts "OK"
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		def list_sensors(device)
			if (list = @redis.list(:sensor, device))
				list.each do |k, v|
					puts "#{k} : #{v[:name]}, #{v[:profile]} (period : #{v[:period]})"
				end
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		def add_sensor_profile(args={})
			args[:type] = :sensor
			begin
				@redis.add_profile args
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		def add_actuator_profile(args={})
			args[:type] = :actuator
			begin
				@redis.add_profile args
			rescue ArgumentError => error
				puts error.message
			end
		end
		
		def list_sensor_profiles
			@redis.list_profiles(:sensor).each do |name, profile|
				puts "#{name} : #{profile[:function]}, #{profile[:rpn]}, #{profile[:unit]}"
			end
		end
		
		def list_actuator_profiles
			@redis.list_profiles(:actuator).each do |name, profile|
				puts "#{name} : #{profile[:function]}"
			end
		end
	end
end

