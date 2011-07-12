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
				puts "#{multi} : #{config["description"]} (supports : #{@redis.support(config["supported"]).join(", ")}"#, #{@redis.list_sensors(multi).size} task(s) running)"
			end
		end
		
		def list_unconfigured
			@redis.list_multis.select {|multi, config| @redis.list_sensors(multi).size == 0}.each do |multi, config|
				puts "#{multi} : #{config["description"]} (supports : #{config["supported"].join(" ")})"
			end
		end
		
		def add_sensor(device, pin, description, profile, period)
			if @redis.add(:sensor, device, pin, {"description" => description, "profile" => profile, "period" => period})
				puts "OK"
			else
				puts "Missing profile or multiplexor"
			end
		end
		
		def add_actuator(device, pin, description, profile)
			if @redis.add(:actuator, device, pin, {"description" => description, "profile" => profile})
				puts "OK"
			else
				puts "Missing profile or multiplexor"
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
		
		def list_sensors(device)
			if (list = @redis.list(:sensor, device))
				list.each do |k, v|
					puts "#{k} : #{v["description"]}, #{v["profile"]} (period : #{v["period"]})"
				end
			else
				puts "The multiplexer doesn't exist"
			end
		end
		
		def add_sensor_profile name, function, rpn, unit
			@redis.add_profile :sensor, name, {"function" => function, "rpn" => rpn, "unit" => unit}
		end
		
		def add_actuator_profile name, function, period = nil
			@redis.add_profile :actuator, name, {"function" => function, "period" => period}
		end
		
		def list_sensor_profiles
			@redis.list_profiles(:sensor).each do |name, profile|
				puts "#{name} : #{profile["function"]}, #{profile["rpn"]}, #{profile["unit"]}"
			end
		end
		
		def list_actuator_profiles
			@redis.list_profiles(:actuator).each do |name, profile|
				puts "#{name} : #{profile["function"]}"
			end
		end
	end
end

