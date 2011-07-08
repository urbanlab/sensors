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
			@serial.add_task(id_multi, sensor, @redis.get_profile(config["profile"])["function"], config["period"]) #TODO must check if multi not registered
		end
		
		@redis.on_deleted_sensor do |id_multi, sensor|
			@serial.rem_task(id_multi, sensor) #TODO registered ? task exists ?
		end
		
		@redis.on_published_value(:actuator) do |multi, pin, value|
			case value
				when 1
					@serial.snd_command(multi, :add, 100, pin)
				when 0
					@serial.snd_command(multi, :remove, pin)
			end
		end
		
		@serial.on_new_multi do |id|
			if (id == 0 or id == 255)  # Unconfigured, bad id
				new_id = (Array(1..255) - @redis.list_multis.keys)[0] # first unused id
				@serial.change_id(id, new_id)
			elsif (not (@redis.knows_multi? id))   # valid id, but not registered
				@redis.set_multi_config(id, {"description" => "no description", "supported" => @serial.list_implementations(id)})
			else
				# TODO Check if the tasks correspond
			end
		end
		
		@serial.on_sensor_value do |id_multi, sensor, value|
			@redis.publish_value(id_multi, sensor, value)
		end
	end
end

demon = Xbee_Demon.new("1")
sleep

