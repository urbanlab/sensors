#!/usr/bin/env ruby
$:.unshift(File.dirname(__FILE__) + '/') unless $:.include?(File.dirname(__FILE__) + '/')
require 'rubygems'
require 'redis-interface-demon'
require 'serial-interface'
require 'logger'
require 'optparse'

=begin
- multiplexer : {:description => "bla", :supported => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {:fonction => "din", :rpn => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {:pin => 13, :fonction => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end
# TODO limiter les accès redis

class Xbee_Demon
	def initialize(network, args)#serial_port = '/dev/ttyUSB0', baudrate = 19200, redis_host = 'localhost', redis_port = 6379, logfile = nil)
		args = {baudrate: 19200, redis_host: 'localhost', redis_port: 6379, logfile: STDERR, level: Logger::WARN, size: 1048576}.merge args
		Thread.abort_on_exception = true
		@log = Logger.new(args[:logfile], 0, args[:logfile])
		@log.level = args[:level]
		@log.datetime_format = "%Y-%m-%d %H:%M:%S"
		@network = network
		@log.info("Starting demon on port #{args[:serial_port]}")
		begin
			@redis = Redis_interface_demon.new(network, args[:redis_host], args[:redis_port], @log)
			@serial = Serial_interface.new(args[:serial_port], args[:baudrate], @log)
		rescue Errno::ECONNREFUSED => e
			@log.fatal("Could not connect to Redis, exiting... error : #{e.message}")
			exit
		rescue Errno::ENOENT => e
			@log.fatal("Could not find receiver, exiting... error : #{e.message}")
			exit
		end
	end
	
	def launch
		trap(:INT){@log.info "Exiting"; exit 0}
		restore_state
	
		@redis.on_new_sensor do |multi, pin, function, period, *options|
			@serial.add_task(multi, pin, function, period, *options)
		end
		
		#@redis.on_new_actu do |id_multi, actu, config|
		#rien à faire ?
		#end
		
		@redis.on_deleted :sensor do |id_multi, sensor|
			ans = @serial.rem_task(id_multi, sensor)
			(ans == true) or (ans == false) # If the tasks didn't exist (ans == false), should remove it from redis
			                                # If the multi didn't answer (ans == nil) should not remove it
		end
		
		@redis.on_deleted :actuator do |id_multi, actuator|
			if @redis.get_config(:actuator, id_multi, actuator) # if the actuator was running, should ensure it will stop
				ans = @serial.rem_task(id_multi, actuator)
				(ans == true) or (ans == false) #delete from redis only if the task is no more running
			else
				true #don't care if the multi knows it, the task wasn't running.
			end
		end
		
		@redis.on_published_value(:actuator) do |multi, pin, value|
			case value.to_i
				when 1
					config = @redis.get_config(:actuator, multi, pin)
					profile = @redis.get_profile(:actuator, config[:profile])
					if (not (config && profile))
						@log.warn("A client tried to switch on an actuator without config or profile")
						next
					end
					period = config[:period] || profile[:period] || 0
					@serial.add_task(multi, pin, profile[:function], period)
				else 
					@serial.rem_task(multi, pin)
			end
		end
		
		# TODO : test
		@redis.on_taken do |id_multi, network|
			if (network == @network) #it's for me !
				@serial.reset(id_multi) #cleaning what the over demon let on the multiplexer
				config = @redis.get_multi_config(id_multi)
				config[:network] = @network
				@redis.set_multi_config(id_multi, config)
			else
				@redis.clean_up(id_multi)
			end
		end

		@serial.on_new_multi do |id|
			config = @redis.get_multi_config(id)
			if (id == 0 or id == 255)  # Unconfigured, bad id
				new_id = (Array(1..255) - @redis.list_multis.keys)[0] # first unused id
				if (@serial.change_id(id, new_id) && @network == 1) #only network 1 will changes the ids...
					@redis.set_multi_config(new_id, {network: 0, description: "no name", supported: @serial.list_implementations(id)})
				end
			elsif (not (@redis.knows_multi? id))   # valid id, but not registered
				@redis.set_multi_config(id, {network: 0, description: "no name", supported: @serial.list_implementations(id)})
			elsif (config[:network]) == @network # registered multiplexer on my network
				restore_multi_state id
			end
		end
		
		@serial.on_sensor_value do |id_multi, sensor, value|
			@redis.publish_value(id_multi, sensor, value)
		end
		
		sleep
	end
	
	def restore_state
		@log.info("Restoring state from database...")
		@redis.list_multis.each do |id_multi, config|
			restore_multi_state id_multi
		end
		@log.info("Restoration complete.")
	end
	
	def restore_multi_state multi_id #TODO solidification ?
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

options = {}

opts = OptionParser.new do |opts|
	opts.banner = "Usage: demon-xbee.rb [options] network"
	
	opts.on("-l", "--logfile FILE", "Log to given FILE (default : stderr)") do |file|
		if file == "stdout" or file == "stderr"
			options[:logfile] = {"stdout" => STDOUT, "stderr" => STDERR}[file]
		else
			begin
				options[:logfile] = File.open file, File::WRONLY | File::APPEND
			rescue Exception => e
				begin
					options[:logfile] = File.open file, File::WRONLY | File::APPEND | File::CREAT
				rescue Exception => e
					puts "Could not open or create the log file, exiting... Error : #{e.message}"
					exit 1
				end
			end
		end
	end
	
	opts.on("-L", "--log-level LEVEL", {"debug" => 0, "info" => 1, "warn" => 2, "error" => 3, "fatal" => 4, "unknown" => 5}, "Verbosity of the logger (can be debug, info, warn, error, fatal or unknown, default warn)") do |level|
		options[:level] = level
	end
	
	opts.on("-p", "--serial-port PORT", "Port where the receiver is plugged (will try any /dev/ttyUSB* by default)") do |serial|
		options[:serial_port] = serial
	end
	
	opts.on("-b", "--baudrate BAUDRATE", Integer, "Baudrate of the receiver (default : 19200)") do |baudrate|
		options[:baudrate] = baudrate
	end
	
	opts.on("-H", "--redis-host HOST", "Host where Redis is running (default : localhost)") do |host|
		options[:redis_host] = host
	end
	
	opts.on("-r", "--redis-port PORT", Integer, "Port where Redis is listening (default : 6379)") do |port|
		options[:redis_port] = port.to_i
	end
	
	opts.on("-s", "--log-size SIZE", Integer, "Maximum logfile size (default : 1048576)") do |size|
		options[:size] = size
	end
	
	opts.on('-h', '--help', 'Show this message') do
		puts opts
		exit
	end
end

if ARGV.size == 0
	puts opts
	exit
end

opts.parse!

if ARGV.size == 1 && ARGV[0].is_integer?
	options[:network] = ARGV[0].to_i
else
	puts "Network must be given and be an integer"
	exit 1
end

demon = Xbee_Demon.new(options.delete(:network), options)
demon.launch




