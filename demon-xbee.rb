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
		r_start_interface(redis_host, redis_port, network)
		@serial = SerialPort.new serial_port, baudrate
		@supported = []
		serial_listener = Thread.new do
			listen_serial
		end
	
		serial_listener.join()
	end
	
	def listen_serial
		loop do
			id_multi, command, *args = s_get_message()@serial.readline.delete("\r\n").split("\s")
			if id_multi.is_integer?
				case command
					when "SENS"
						#rpn = JSON.parse(@redis.hget(get_redis_path(id_multi), args[0]))[:rpn]#"network:#{@network}:multiplexers:#{id_multi}:sensors:#{args[0]}"))[:rpn]
						value = args[1]#rpn_solve(args[1], rpn)
						r_publish_value(id_multi, args[0], value) if (r_get_multi_keys).include? id_multi
					when "NEW"
						puts "new id " << id_multi.to_s
						if (id_multi == "0" or id_multi == "255") #unconfigured, must set an id.
							new_id = (Array("1".."255") - r_get_multi_keys)[0]
							@serial.write(id_multi.to_s << " i " << new_id.to_s)
						elsif not ((r_get_multi_keys).include? id_multi) #unconfigured with a valid id
							new_multi(id_multi.to_i)	
						else
							p r_get_multi_config id_multi
							p JSON.parse(@redis.hget(get_redis_path() << ":multiplexers", id_multi))["supported"]
						end
					when "LIST"
						@supported[id_multi.to_i].write(args.join(" "))# if (@supported[id_multi.to_i])
						@supported[id_multi.to_i].close
				end
			end
		end
	end
	
	def new_multi(id_multi)
		rd, wr = IO.pipe
		@supported[id_multi] = wr
		waiting = Thread.new{
			supported = rd.read
			rd.close
			supported = supported.split("\s")
			r_set_multi_config(id_multi, {"description" => "unconfigured", "supported" => supported})
		}
		@serial.write(id_multi.to_s + " l")
	end

end

class String
  def is_integer?
    begin Integer(self) ; true end rescue false
  end
end

demon = Xbee_Demon.new("1")


