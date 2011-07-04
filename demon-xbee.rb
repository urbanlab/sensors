require 'rubygems'
require 'json'
require 'redis'
require 'serialport'


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
		@network = network
		@serial = SerialPort.new serial_port, baudrate
		@redis = Redis.new :host => redis_host, :port => redis_port
		@supported = []

		serial_listener = Thread.new do
			listen_serial
		end
	
		serial_listener.join()
	end
	
	def listen_serial
		loop do
			id_multi, command, *args = @serial.readline.delete("\r\n").split("\s")
			if id_multi.is_integer?
				case command
					when "SENS"
						#rpn = JSON.parse(@redis.hget(get_redis_path(id_multi), args[0]))[:rpn]#"network:#{@network}:multiplexers:#{id_multi}:sensors:#{args[0]}"))[:rpn]
						value = args[1]#rpn_solve(args[1], rpn)
						publish_value(id_multi, args[0], value)
					when "NEW"
						puts "new id " << id_multi.to_s
						if (id_multi == "0" or id_multi == "255") #unconfigured, must set an id.
							puts "no id"
							new_id = (Array("1".."255") - @redis.hkeys(get_redis_path() << ":multiplexers"))[0]
							p @redis.hkeys(get_redis_path() << ":multiplexers")
							@serial.write(id_multi.to_s << " i " << new_id.to_s)
						elsif not (@redis.hkeys(get_redis_path() << ":multiplexers").include? id_multi) #unconfigured with a valid id
							puts "new ard"
							new_multi(id_multi.to_i)
							#@redis.hset(get_redis_path() << ":multiplexers", id_multi, {:description => "unconfigured", :supported => ["dunno", "yup"]}.to_json)
						else
							puts "known ard"
							puts "he supports"
							p @redis.hget(get_redis_path() << ":multiplexers", id_multi)
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
			@redis.hset(get_redis_path() << ":multiplexers", id_multi, {:description => "unconfigured", :supported => supported}.to_json)
		}
		@serial.write(id_multi.to_s + " l")
		p "alive"
	end
	
	def publish_value(multiplexer, sensor, value)
		@redis.publish(get_redis_path(multiplexer, sensor), [value, Time.now.to_i].to_json)#"network:#{@network}:multiplexers:#{multiplexer}:sensors:#{sensor}", [value, Time.now.to_i].to_json)
		@redis.hset(get_redis_path(multiplexer), sensor, [value, Time.now.to_i].to_json)#"network:#{@network}:multiplexers:#{multiplexer}:sensors:#{sensor}", [value, Time.now.to_i].to_json)
	end
	
	def get_redis_path(multiplexer = false, sensor = false)
		path = "network:#{@network}"
		path << ":multiplexers:#{multiplexer}" if multiplexer
		path << ":sensors:#{sensor}" if sensor
		path
	end
end

class String
  def is_integer?
    begin Integer(self) ; true end rescue false
  end
end

demon = Xbee_Demon.new("1")


