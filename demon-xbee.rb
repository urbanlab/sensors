require 'rubygems'
require 'json'
require 'serialport'
require 'redis-interface.rb'
require 'serial-interface.rb'


=begin
- multiplexer : {:description => "bla", :supported => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {:fonction => "din", :rpn => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {:pin => 13, :fonction => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end

class Xbee_Demon
	include Redis_interface
	def initialize(network, serial_port = '/dev/ttyUSB0', baudrate = 19200, redis_host = 'localhost', redis_port = 6379)
	
		Thread.abort_on_exception = true
		r_start_interface(redis_host, redis_port, network)
		@serial = SerialPort.new serial_port, baudrate
		@supported = []
		serial_listener = Thread.new {
			listen_serial
		}
		
		r_on_new_sensor do |id_multi, sensor, config|
			puts id_multi.to_s + " a " + config["function"] + " " + config["period"].to_s + " " + sensor.to_s
			@serial.write(id_multi.to_s + " a " + config["function"] + " " + config["period"].to_s + " " + sensor.to_s + "\n")
		end
	
		serial_listener.join()
	end
	
	def listen_serial
		loop do
			id_multi, command, *args = @serial.readline.delete("\r\n").split("\s")
			if id_multi and id_multi.is_integer?
				case command
					when "SENS"
						# TODO check if the pin is registered
						#rpn = JSON.parse(@redis.hget(get_redis_path(id_multi), args[0]))[:rpn]#"network:#{@network}:multiplexers:#{id_multi}:sensors:#{args[0]}"))[:rpn]
						value = args[1]#rpn_solve(args[1], rpn)
						r_publish_value(id_multi, args[0], value)# if (r_get_multi_keys).include? id_multi.to_s
					when "NEW"
						if (id_multi == "0" or id_multi == "255")              # unconfigured, must set an id.
							new_id = (Array("1".."255") - r_get_multi_keys)[0] # first unused id
							@serial.write(id_multi.to_s << " i " << new_id.to_s)
						elsif not ((r_get_multi_keys).include? id_multi) #unconfigured with a valid id
							new_multi(id_multi.to_i)	
						else
							# TODO Check if the tasks correspond
						end
					when "LIST"
						if (@supported[id_multi.to_i])
							@supported[id_multi.to_i].write(args.join(" "))
							@supported[id_multi.to_i].close
						end
				end
			end
		end
	end
	
	def new_multi(id_multi)
		rd, wr = IO.pipe
		@supported[id_multi] = wr
		wait_for(rd) { |supported|
			r_set_multi_config(id_multi, {"description" => "unconfigured", "supported" => supported.split("\s")})
		}
		@serial.write(id_multi.to_s + " l")
	end
	
	def wait_for(pipe, &block)
		Thread.new{
			message = pipe.read
			pipe.close
			yield message
		}
	end

end

class String
  def is_integer?
    begin Integer(self) ; true end rescue false
  end
end

demon = Xbee_Demon.new("1")


