require 'rubygems'
require 'serialport'
require 'timeout'
require 'thread'
require 'io/wait'
require 'logger'

CMD = { :list => "l", :add => "a", :remove => "d", :tasks => "t" , :id => "i", :reset => "r" }
ANS = { :sensor => "SENS", :new => "NEW", :implementations => "LIST", :tasks => "TASKS" , :ok => "OK", :add => "ADD", :remove => "DEL"}
#TODO verify the execution of add, id and remove
class Serial_interface
	def initialize port, baudrate, logger = Logger.new(nil), timeout = 1, retry_nb = 3
		@log = logger
		@baudrate = baudrate
		@down_ports = []
		@port = port || search_port
		@serial = SerialPort.new @port, @baudrate
		@wait_for = {} # {pattern => wpipe}
		@timeout = timeout
		@retry = retry_nb
		# Thread.abort_on_exception = true
		listener = Thread.new {
			process_messages
		}
	end
	
	# Listen to the incoming messages and process them according to @wait_for
	#
	def process_messages
		loop do
			buff = ""
			while not buff.end_with?("\r\n")
				i = 0
				begin
					@serial.wait
					buff << @serial.gets
				rescue StandardError => e
					@log.error("The serial line had a problem : #{e.message}, retrying...")
					@serial.close
					sleep 1
					@port = search_port
					sleep 1
					@serial = SerialPort.new @port, @baudrate
					retry				
				end
			end
			@log.debug("Received \"#{buff.delete("\r\n")}\"")
			accepted = false
			#TODO :@wait_for.detect {|pattern, pipe| buff.match(pattern)}
			catch :accepted_message do
				@wait_for.each do |pattern, pipe|
					if (buff.match(pattern))
						pipe.write(buff)
						pipe.close
						@wait_for.delete pattern
						throw :accepted_message
						break
					end
				end
				@log.warn("Received an unhandled message : #{buff}")
			end
		end
	end
	
	# Reset a multiplexer : delete every task running (keep the id)
	#
	def reset(multi)
		snd_message(/^#{multi} RST/, multi, :reset)
	end
	
	# Add a task to a multiplexer. Return true if it's a success. (args are the
	# optionnal argument of the firmware function)
	#
	def add_task(multi, pin, function, period, *args)
		args.delete nil
		if snd_message(/^#{multi} ADD #{pin}/, multi, :add, function, period, pin, *args) == "KO"
			@log.warn("Could not add task \"#{function}\" on #{multi}:#{pin}")
			return false
		end
		return true
	end
	
	# Stop a task and execute its stopping function
	#
	def rem_task(multi, pin)
		if snd_message(/^#{multi} DEL #{pin}/, multi, :remove, pin) == "KO"
			@log.warn("Could not remove task #{multi}:#{pin}")
			return false
		end
		return true
	end
	
	# Modify the id of a multiplexer. Tasks will still run
	#
	def change_id(old, new)
		snd_message(/^#{new} ID/, old, :id, new)
		#TODO : register
	end
	
	# Get the list of implementations supported by an arduino
	# in an array
	#
	def list_implementations(multi) # TODO retour si ça ne marche pas
		snd_message(/^#{multi} LIST/, multi, :list).split(" ")
	end
	
	# List the running tasks of an arduino in a hash
	#
	def list_tasks(multi)
		ans = snd_message(/^#{multi} TASKS/, multi, :tasks)
		Hash[*ans.scan(/(\d+):(\w+)/).collect{|p| [p[0].to_i, p[1]]}.flatten]
	end
	
	# Callback when a multiplexer is plugged
	# block has 1 int argument : multiplexer's id.
	#
	def on_new_multi(&block)
		Thread.new do
			loop do
				yield(brutal_wait_for(/^\d+ NEW/).scan(/^\d+/)[0].to_i)
			end
		end
	end
	
	# Callback when a multiplexer send a value of one of his sensor
	# block has 3 int arguments : the multiplexer's id, pin number and value.
	#
	def on_sensor_value(&block)
		Thread.new do
			loop do
				id, sensor, value = brutal_wait_for(/^\d+ SENS/).scan(/\d+/)
				yield(id.to_i, sensor.to_i, value.to_i)
			end
		end
	end
	
	private
	
	def search_port
		port = nil
		until port
			@down_ports.push @port if @port
			candidates = Dir.glob("/dev/ttyUSB*")
			not_tested = candidates - @down_ports
			if not_tested.size == 0
				@down_ports.clear
				not_tested = candidates
			end
			port = case not_tested.size
				when 0
					@log.error("No /dev/ttyUSB available, demon won't anything while not fixed")
					nil
				when 1
					@log.info("Trying with port #{candidates[0]}")
					not_tested[0]
				else
					@log.warn("More than 1 port are available, taking #{candidates[0]}")
					not_tested[0]
			end
			sleep 1
		end
		port
	end
	
	def snd_message(pattern, multi, command, *args)
		msg = "#{multi} #{CMD[command]} #{args.join(" ")}".chomp(" ") + "\n"
		@log.debug("Sent : \"#{msg.delete("\n")}\"")
		@serial.write msg
		if pattern
			begin
				wait_for(pattern)
			rescue Timeout::Error => e
				@log.error("The multiplexer #{multi} did not answered to the command \"#{command}\"")
			end
		end
	end
	
	def wait_for(pattern)
		i = 0
		rd, wr = IO.pipe
		@wait_for[pattern] = wr
		begin
			Timeout.timeout(@timeout){rd.read.match(pattern).post_match.lstrip.chomp}
		rescue Timeout::Error => e
			((i+=1) < @retry)? retry : raise(e)
		end
	end
	
	def brutal_wait_for (pattern)
		i = 0
		rd, wr = IO.pipe
		@wait_for[pattern] = wr
		ans = rd.read
		ans
	end
end

class String
	def is_integer?
		begin Integer(self) ; true end rescue false
	end
	def is_numeric?
		begin Float(self) ; true end rescue false
	end
end


