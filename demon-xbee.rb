#!/usr/bin/env ruby

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
		args = {baudrate: 19200, redis_host: 'localhost', redis_port: 6379, logger: Logger.new(nil)}.merge args
		Thread.abort_on_exception = true
		@log = args[:logger]
		redislogger = @log.dup
		redislogger.progname = "Redis"
		seriallogger = @log.dup
		seriallogger.progname = "Serial"
		
		@log.info("Starting demon on port #{args[:serial_port]}")
		begin
			port = args[:serial_port]
			@redis = Redis_interface_demon.new(network, args[:redis_host], args[:redis_port], redislogger)
			@serial = Serial_interface.new(port, args[:baudrate], seriallogger)
		rescue Errno::ECONNREFUSED => e
			@log.fatal("Could not connect to Redis, exiting... error : #{e.message}")
			exit
		rescue Errno::ENOENT => e
			@log.fatal("Could not find receiver, exiting... error : #{e.message}")
			exit
		end
	end
	
	def launch
		restore_state
	
		@redis.on_new_sensor do |multi, pin, function, period, *options|
			@serial.add_task(multi, pin, function, period, *options)
		end
		
		#@redis.on_new_actu do |id_multi, actu, config|
		#rien à faire ?
		#end
		
		@redis.on_deleted :sensor do |id_multi, sensor|
			@serial.rem_task(id_multi, sensor) #TODO registered ? task exists ?
		end
		
		@redis.on_deleted :actuator do |id_multi, actuator|
			@serial.rem_task(id_multi, actuator) if get_config(:actuator, id_multi, actuator).state
		end
		
		@redis.on_published_value(:actuator) do |multi, pin, value|
			case value.to_i
				when 1 #TODO test existence profile
					config = @redis.get_config(:actuator, multi, pin)
					profile = @redis.get_profile(:actuator, config[:profile])
					period = config[:period] || profile[:period] || 0#profile.has_key?(:period)? period = profile[:period] : period = 0 #period = 0 => don't loop
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
				restore_multi_state id
				#@redis.list(:sensor, id ).each do |pin, config| #plante si profile faux TODO
				#	profile = @redis.get_profile(:sensor, config[:profile])
				#	@serial.add_task(id, pin, profile[:function], config[:period], *[profile[:option1], profile[:option2]])
				#end
				#rien à faire pour les actus, sauf peut être remettre dans meme état ?		
			end
		end
		
		@serial.on_sensor_value do |id_multi, sensor, value|
			@redis.publish_value(id_multi, sensor, value)
		end
	end
	
	def restore_state
		@log.info("Restoring state from database...")
		@redis.list_multis.each do |id_multi, config|
			restore_multi_state id_multi
		end
		@log.info("Restoration complete.")
	end
	
	def restore_multi_state multi_id
		config = @redis.get_multi_config(multi_id)
		if (@serial.ping multi_id)
			@redis.list(:sensor, multi_id).each do |pin, sensor_config|
				profile = @redis.get_profile(:sensor, sensor_config[:profile])
				period = sensor_config[:period] || profile[:period] || 0
				@serial.add_task(multi_id, pin, profile[:function], period, *[profile[:option1], profile[:option2]])
			end
			config[:state] = true
			@redis.set_multi_config(multi_id, config)
		else
			@log.warn "Multiplexer #{multi_id} seems to be disconnected."
			config[:state] = false
			@redis.set_multi_config(multi_id, config)
		end
	end
end

log = Logger.new STDOUT
log.level = Logger::DEBUG
log.progname = "Demon"
log.datetime_format = "%Y-%m-%d %H:%M:%S"
trap(:INT){throw :interrupted}
begin #TODO : don't work ?
	demon = Xbee_Demon.new("1", logger: log)
	demon.launch
rescue Errno::ECONNREFUSED => e
	@log.fatal("Lost connection with Redis, exiting... error : #{e.message}")
	exit
rescue Errno::ENOENT => e
	@log.fatal("Lost connection with the receiver, exiting... error : #{e.message}")
	exit
rescue Errno::EIO => e
	@log.fatal("Unknown error : #{e.message}")
	exit
end
catch(:interrupted){sleep}
log.info("Exiting...")



