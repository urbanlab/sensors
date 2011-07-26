require 'rubygems'
require 'json'
require 'serialport'
require './redis-interface-demon.rb'
require './serial-interface.rb'
require 'logger'


=begin
- multiplexer : {:description => "bla", :supported => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {:fonction => "din", :rpn => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {:pin => 13, :fonction => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end

class Xbee_Demon
	def initialize(network, args)#serial_port = '/dev/ttyUSB0', baudrate = 19200, redis_host = 'localhost', redis_port = 6379, logfile = nil)
		args = {serial_port: '/dev/ttyUSB0', baudrate: 19200, redis_host: 'localhost', redis_port: 6379, logger: Logger.new(nil)}.merge args
		Thread.abort_on_exception = true
		@log = args[:logger]
		@log.progname = "Demon"
		@redis = Redis_interface_demon.new(network, args[:redis_host], args[:redis_port])
		@serial = Serial_interface.new(args[:serial_port], args[:baudrate], args[:logger])
		
		@redis.on_new_sensor do |multi, pin, function, period, *options|
			@serial.add_task(multi, pin, function, period, *options)
		end
		
		@redis.on_new_actu do |id_multi, actu, config|
		#rien à faire ?
		end
		
		@redis.on_deleted_sensor do |id_multi, sensor|
			@serial.rem_task(id_multi, sensor) #TODO registered ? task exists ?
		end
		
		@redis.on_published_value(:actuator) do |multi, pin, value|
			case value.to_i
				when 1 #TODO test existence profile
					config = @redis.get_config(:actuator, multi, pin)
					profile = @redis.get_profile(:actuator, config[:profile])
					profile.has_key?(:period)? period = profile[:period] : period = 10000000 #ugly
					@serial.add_task(multi, pin, profile[:function], period)
				else 
					@serial.rem_task(multi, pin)
			end
		end

		@serial.on_new_multi do |id|
			if (id == 0 or id == 255)  # Unconfigured, bad id
				new_id = (Array(1..255) - @redis.list_multis.keys)[0] # first unused id
				@serial.change_id(id, new_id)
			elsif (not (@redis.knows_multi? id))   # valid id, but not registered
				@redis.set_multi_config(id, {:description => "no name", :supported => @serial.list_implementations(id)})
			else                                   # Known multi that has been reseted
				@redis.list(:sensor, id ).each do |pin, config|
					profile = @redis.get_profile(:sensor, config[:profile])
					@serial.add_task(id, pin, profile[:function], config[:period], *[profile[:option1], profile[:option2]])
				end
				#rien à faire pour les actus, sauf peut être remettre dans meme état ?		
			end
		end
		
		@serial.on_sensor_value do |id_multi, sensor, value|
			@redis.publish_value(id_multi, sensor, value)
		end
	end
end
log = Logger.new STDOUT
log.level = Logger::DEBUG
demon = Xbee_Demon.new("1", logger: log)
sleep

