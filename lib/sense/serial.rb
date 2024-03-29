require 'rubygems'
require 'timeout'
require 'thread'
require 'io/wait'
require 'logger'
require 'sense/extensions'
require 'sense/xbee'
require 'serialport'

module Sense
	# Interface to serial port in order to get and send message to the multiplexers
	#
	class Serial
		# List of possible commands to send to the multiplexers
		CMD = { list: "l", add: "a", remove: "d", tasks: "t" , id: "i", reset: "r", ping: "p" }
	
		# List of possible answers
		ANS = { sensor: "SENS", new: "NEW", implementations: "LIST", tasks: "TASKS" , ok: "OK", add: "ADD", remove: "DEL"}
	
		# Construction of the interface
		# @param [Integer] port Port where the xbee receiver is plugged (eg. '/dev/ttyUSB0')
		# @param [Logger] logger to log informations concerning the serial line
		# @param [Integer] timeout Time in second before a command without answer
		# is considered as lost
		# @param [Integer] retry_nb Number of time to retry to send a command before
		# the multiplexer is considered as disconnected
		def initialize port, logger = Logger.new(nil), timeout = 0.4, retry_nb = 3
			@down = false
			@log = logger
			@baudrate = 9600
			@down_ports = []
			@port = port || search_port
			@serial = File.open(@port, "w+")
			@serial.flush
			@wait_for = {} # {pattern => wpipe}
			@timeout = timeout
			@retry = retry_nb
			listener = Thread.new {
				process_messages
			}
		end
	
		# Listen to the incoming messages and process them according to @wait_for
		#
		def process_messages
			loop do
				buff = ""
				old_time = 0
				while not buff.end_with?("\n")
					i = 0
					if (Time.now.to_f - old_time > 0.1) && (not buff.empty?) # only work when gets is non blocking (seems to become non blocking after some time...)
						@log.debug("Received an incomplete message")
						buff.clear
					end
					begin
						#@serial.wait
						buff << @serial.gets("\n")
						old_time = Time.now.to_f
					rescue StandardError => e
						@log.error("The serial line had a problem : #{e.message}, retrying...")
						@serial.close
						sleep 1
						@port = search_port
						sleep 1
						@serial = SerialPort.new(@port, @baudrate)#File.open(@port, "w+")
						retry				
					end
				end
				if not buff.ascii_only?
					@log.debug("Received a malformed message")
					buff.clear
					next
				end
				@log.debug("Received \"#{buff.delete("\r\n")}\"")
				pattern, pipe = @wait_for.detect{|pattern, pipe| buff.match(pattern)}
				if pattern
					pipe.write(buff)
					pipe.close
					@wait_for.delete pattern
				else
					@log.debug("Received an unhandled message : #{buff}")
				end
			end
		end
	
		# Reset a multiplexer : delete every task running (keep the id)
		# @return [boolean] True if the multiplexer was reseted
		# @macro [new] multi
		#   @param [Integer] multi Id of the multiplexer
		#
		def reset(multi)
			snd_message(/^#{multi} RST/, multi, :reset) == "" ? true : nil
		end
	
		# Ping a multiplexer : test if it is alive
		# @macro multi
		# @return [boolean] True if the multiplexer is alive
		def ping(multi)
			snd_message(/^#{multi} PONG/, multi, :ping) == "" ? true : nil
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
			snd_message(/^#{new} ID/, old, :id, new) == "" ? true : nil
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
	
		# Look for serial ports to listen to.
		#
		def search_port
			port = nil
			until port
				@down_ports.push @port if @port
				candidates = Dir.glob("/dev/ttyUSB*")
				not_tested = candidates - @down_ports
				if not_tested.size == 0
					@log.error("No xbee available, demon won't anything while not fixed") unless @down
					@down = true
					@down_ports.clear
					not_tested = candidates
				end
				port = case not_tested.size
					when 0
						#@down = true
						nil
					else
						port = not_tested.find do |port|
							@log.debug("Trying with #{port}")
							if Sense::Xbee.setup(port, :daemon)
								@log.info("Found an xbee on #{port}, use it as receiver")
								true
							else
								@down_ports.push(port)
								@log.debug("#{port} is not an xbee")
								false
							end
						end
						@down = false if port
						port
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
			begin
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
								@log.info("The multiplexer #{multi} did not answered to the command \"#{command}\"")
								nil
							end
						end
					end
				end
			rescue StandardError => e
				@log.error("Could not send message : serial is down")
				nil
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

