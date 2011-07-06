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
	
		def list
			@redis.get_multis_config.each do |multi, config|
				puts "#{multi} : #{config["description"]} (supports : #{config["supported"].join(" ")}, #{@redis.get_sensors_config(multi).size} task(s) running)"
			end
		end
		
		def list_unconfigured
			@redis.get_multis_config.select {|multi, config| @redis.get_sensors_config(multi).size == 0}.each do |multi, config|
				puts "#{multi} : #{config["description"]} (supports : #{config["supported"].join(" ")})"
			end
		end
		
		def add_sensor(device, pin, function, period)
			@redis.set_sensor_config(device, pin, {"function" => function, "period" => period.to_i})
		end
		
		def set_description(device, description)
			config = @redis.get_multi_config(device)
			config["description"] = description
			@redis.set_multi_config(device, config)
		end
		
		def remove_sensor(device, pin)
			@redis.remove_sensor device, pin
		end
		
		def get_sensors_config(device)
			@redis.get_sensors_config(device).each do |k, v|
				puts "#{k} : #{v["function"]} (period : #{v["period"]})"
			end
		end
	end
end

