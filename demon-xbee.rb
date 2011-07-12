require 'rubygems'
require 'json'
require 'serialport'
require './redis-interface.rb'
require './serial-interface.rb'


=begin
- multiplexer : {:description => "bla", :supported => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {:fonction => "din", :rpn => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {:pin => 13, :fonction => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end

class Xbee_Demon
	def initialize(network, serial_port = '/dev/ttyUSB0', baudrate = 19200, redis_host = 'localhost', redis_port = 6379)
		Thread.abort_on_exception = true
		@redis = Redis_interface.new(network, redis_host, redis_port)
		@serial = Serial_interface.new serial_port, baudrate
		
		@redis.on_new_sensor do |id_multi, sensor, config|
			@serial.add_task(id_multi, sensor, @redis.get_profile(:sensor, config["profile"])["function"], config["period"]) #TODO must check if multi not registered
		end
		
		@redis.on_new_actu do |id_multi, actu, config|
		#mmm nothing to do ?
		end
		
		@redis.on_deleted_sensor do |id_multi, sensor|
			@serial.rem_task(id_multi, sensor) #TODO registered ? task exists ?
		end
		
		@redis.on_published_value(:actuator) do |multi, pin, value|
			case value.to_i
				when 1
					config = @redis.get_config(:actuator, multi, pin)
					profile = @redis.get_profile(:actuator, config["profile"])
					profile.has_key?("period")? period = profile["period"] : period = 10000000 #ugly
					@serial.add_task(multi, pin, profile["function"], period)
				else 
					@serial.rem_task(multi, pin)

			end
		end
		
		# TODO rewrite for actus...
		@redis.on_new_config do |config|
			@redis.flushdb
			config["profile"]["sensor"].each do |name, profile|
				@redis.add_profile(:sensor, name, profile)
			end
			config["profile"]["actuator"].each do |name, profile|
				@redis.add_profile(:actuator, name, profile)
			end
			config["multiplexers"].each do |multi_id, multi_config|
				@serial.reset multi_id
				multi_config["supported"] = @serial.list_implementations(multi_id.to_i)
				@redis.set_multi_config(multi_id.to_i, multi_config)
				multi_config["sensors"].each do |sens_id, sens_config|
					@serial.add_task(multi_id.to_i, sens_id.to_i, @redis.get_profile(:sensor, sens_config["profile"])["function"], sens_config["period"])
					@redis.add(:sensor, multi_id.to_i, sens_id.to_i, sens_config)
				end
				multi_config["actuators"].each do |actu_id, actu_config|
					@redis.add(:actuator, multi_id.to_i, actu_id.to_i, actu_config)
				end
			end
		end
		
		@serial.on_new_multi do |id|
			if (id == 0 or id == 255)  # Unconfigured, bad id
				new_id = (Array(1..255) - @redis.list_multis.keys)[0] # first unused id
				@serial.change_id(id, new_id)
			elsif (not (@redis.knows_multi? id))   # valid id, but not registered
				@redis.set_multi_config(id, {"description" => "no description", "supported" => @serial.list_implementations(id)})
			else                                   # Known multi that has been reseted
				@redis.list(:sensor, id ).each do |pin, config|
					profile = @redis.get_profile(:sensor, config["profile"])
					@serial.add_task(id, pin, profile["function"], config["period"])
				end
				#rien à faire pour les actus, sauf peut être remettre dans meme état ?		
			end
		end
		
		@serial.on_sensor_value do |id_multi, sensor, value|
			@redis.publish_value(id_multi, sensor, value)
		end
	end
end

demon = Xbee_Demon.new("1")
sleep

