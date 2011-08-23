require 'rubygems'
require 'serialport'
require 'timeout'
require 'thread'
require 'io/wait'
require 'logger'
require 'sense/extensions'

module Sense
	# Interface to serial port in order to get and send message to the multiplexers
	#
	class Serial_interface
		# List of possible commands to send to the multiplexers
		CMD = { list: "l", add: "a", remove: "d", tasks: "t" , id: "i", reset: "r", ping: "p" }
	
		# List of possible answers
		ANS = { sensor: "SENS", new: "NEW", implementations: "LIST", tasks: "TASKS" , ok: "OK", add: "ADD", remove: "DEL"}
	
		# Construction of the interface
		# @param [Integer] port Port where the xbee receiver is plugged (eg. '/dev/ttyUSB0')
		# @param [Integer] baudrate Baudrate communication (probably 19200)
		# @param [optional, Logger] logger to log informations concerning the serial line
		# @param [Integer] timeout Time in second before a command without answer
		# is considered as lost
		# @param [Integer] retry_nb Number of time to retry to send a command before
		# the multiplexer is considered as disconnected
		def initialize port, baudrate, logger = Logger.new(nil), timeout = 1, retry_nb = 3
			@down = false
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
				while not buff.end_with?("\n")
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
				pattern, pipe = @wait_for.detect{|pattern, pipe| buff.match(pattern)}
				if pattern
					pipe.write(buff)
					pipe.close
					@wait_for.delete pattern
				else
					@log.warn("Received an unhandled message : #{buff}")
				end
			end
		end
	
		# Reset a multiplexer : delete every task running (keep the id)
		# @return [boolean] True if the multiplexer was reseted
		# @macro [new] multi
		#   @param [Integer] multi Id of the multiplexer
		#
		def reset(multi)
			snd_message(/^#{multi} RST/, multi, :reset) == ""
		end
	
		# Ping a multiplexer : test if it is alive
		# @macro multi
		# @return [boolean] True if the multiplexer is alive
		def ping(multi)
			snd_message(/^#{multi} PONG/, multi, :ping) == ""
		end
	
		# Add a task to a multiplexer.
		# @return [boolean] true if it's a success, false if the multi refused, and nil if nobody answered or invalid answer
		# @macro multi
		# @param [Integer] pin the pin where the device is plugged
		# @param [String] function Arduino function
		# @param [Integer] period Duration beetween 2 tests in ms or 0 to not loop
		# @param [Integer] *args optional other arguments (see function description)
		#
		def add_task(multi, pin, function, period, *args)
			args.delete nil
			case snd_message(/^#{multi} ADD #{pin}/, multi, :add, function, period, pin, *args)
				when "OK"
					true
				when "KO"
					@log.warn("The multiplexer #{multi}:#{pin} refused to add task \"#{function}\"")
					false
				else
					nil
			end
		end
	
		# Stop a task and execute its stopping function
		# @return [boolean] true if this was a success, false if nothing was removed, nil if nobody answered, or invalid answer
		# @macro multi
		# @param [Integer] pin Pin where the device was
		#
		def rem_task(multi, pin)
			case snd_message(/^#{multi} DEL #{pin}/, multi, :remove, pin)
				when "OK"
					true
				when "KO"
					@log.warn("The multiplexer #{multi} refused to remove task on pin #{pin}")
				else
					nil
			end
		end
	
		# Modify the id of a multiplexer. Tasks will still run
		# @return [boolean] true if somebody change its id
		# @param [Integer] old Id of the multiplexer before the change
		# @param [Integer] new Id of the multiplexer after the change
		#
		def change_id(old, new)
			snd_message(/^#{new} ID/, old, :id, new) == ""
		end
	
		# Get the list of implementations supported by an arduino
		# @macro multi
		# @return [Array<String>] or nil if no answer
		#
		def list_implementations(multi)
			ans = snd_message(/^#{multi} LIST/, multi, :list)
			ans.split(" ") if ans
		end
	
		# List the running tasks of a multiplexer
		# @macro multi
		# @return [Hash] in form +{pin => task}+ or nil if no answer
		#
		def list_tasks(multi)
			ans = snd_message(/^#{multi} TASKS/, multi, :tasks)
			Hash[*ans.scan(/(\d+):(\w+)/).collect{|p| [p[0].to_i, p[1]]}.flatten] if ans
		end
	
		# Callback when a multiplexer is plugged
		# @yield [Integer] Id of the plugged multiplexer
		#
		def on_new_multi
			Thread.new do
				loop do
					yield(brutal_wait_for(/^\d+ NEW/).scan(/^\d+/)[0].to_i)
				end
			end
		end
	
		# Callback when a multiplexer send a value of one of his sensor
		# @yield [multi_id, pin, value] Processing of the value
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
	
		# Look for serial ports to listen to
		#
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
						@log.error("No /dev/ttyUSB available, demon won't anything while not fixed") unless @down
						@down = true
						nil
					when 1
						@log.info("Trying with port #{candidates[0]}")
						@down = false
						not_tested[0]
					else
						@log.info("More than 1 port are available, taking #{candidates[0]}")
						@down = false
						not_tested[0]
				end
				sleep 1
			end
			port
		end
	
		# Send a message, wait for the answer and return the answer
		# @param [Regexp] pattern The pattern that the answer must match
		# @param [Integer] multi The multiplexer that will receive the message
		# @param [Symbol] command The command sent (must be a key of CMD)
		# @param args The arguments of the command
		#
		def snd_message(pattern, multi, command, *args)
			msg = "#{multi} #{CMD[command]} #{args.join(" ")}".chomp(" ") + "\n"
			if @serial.closed?
				@log.error("Could not send the command #{command}, the receiver isn't available")
			else
				@serial.write msg
				@log.debug("Sent : \"#{msg.delete("\n")}\"")
				if pattern
					i = 0
					begin
						wait_for(pattern)
					rescue Timeout::Error => e
						if (i+=1) < @retry
							@serial.write msg
							@log.debug("Sent : \"#{msg.delete("\n")}\"")
							retry
						else
							@log.warn("The multiplexer #{multi} did not answered to the command \"#{command}\"")
							nil
						end
					end
				end
			end
		end
	
		# Wait for a pattern and return what it returned
		# @param [Regexp] pattern The pattern of the message
		#
		def wait_for(pattern)
			i = 0
			rd, wr = IO.pipe
			@wait_for[pattern] = wr
			Timeout.timeout(@timeout){rd.read.match(pattern).post_match.lstrip.chomp}
		end
	
		# Wait for a pattern and return the full message
		# @param [Regexp] pattern The pattern of the message
		#
		def brutal_wait_for (pattern)
			i = 0
			rd, wr = IO.pipe
			@wait_for[pattern] = wr
			ans = rd.read
			ans
		end
	end
end

