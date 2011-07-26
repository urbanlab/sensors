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
		@serial = SerialPort.new port, baudrate
		@wait_for = {} # {pattern => wpipe}
		@timeout = timeout
		@retry = retry_nb
		@log = logger
		# Thread.abort_on_exception = true
		listener = Thread.new {
			process_messages
		}
	end
	
	def process_messages
		loop do
			buff = ""
			while not buff.end_with?("\r\n")
				i = 0
				begin
					@serial.wait
					buff << @serial.gets
				rescue StandardError => e
					if (i+=1) < @retry
						@log.error("The serial line had a problem : #{e.message}, retrying...")
						sleep 1
						retry
					else
						@log.fatal("The serial line seems to be down.")
						raise e
					end					
				end
			end
			@log.debug("Received \"#{buff.delete("\r\n")}\"")
			accepted = false
			@wait_for.each do |pattern, pipe|
				if (buff.match(pattern))
					pipe.write(buff)
					pipe.close
					accepted = true
					break
				end
			end
			@log.warn("Received an unhandled message : #{buff}") unless accepted
		end
	end
	
	def reset(multi)
		snd_message(/^#{multi} RST/, multi, :reset)
	end
	
	def add_task(multi, pin, function, period, *args)
		args.delete nil
		if snd_message(/^#{multi} ADD #{pin}/, multi, :add, function, period, pin, *args) == "KO"
			@log.warn("Could not add task \"#{function}\" on #{multi}:#{pin}")
			return false
		end
		return true
	end
	
	def rem_task(multi, pin)
		if snd_message(/^#{multi} DEL #{pin}/, multi, :remove, pin) == "KO"
			@log.warn("Could not remove task #{multi}:#{pin}")
			return false
		end
		return true
	end
	
	def change_id(old, new)
		snd_message(/^#{new} ID/, old, :id, new)
		#TODO : register
	end
	
	def list_implementations(multi)
		snd_message(/^#{multi} LIST/, multi, :list)
	end
	
	def list_tasks(multi)
		ans = snd_message(/^#{multi} TASKS/, multi, :tasks)
		Hash[*ans.scan(/(\d+):(\w+)/).collect{|p| [p[0].to_i, p[1]]}.flatten]
	end
	
	# block has 1 int argument : multiplexer's id.
	def on_new_multi(&block)
		Thread.new do
			loop do
				yield(brutal_wait_for(/^\d+ NEW/).scan(/^\d+/)[0].to_i)
			end
		end
	end
	
	# block has 3 int arguments : the multiplexer's id, pin number and value.
	def on_sensor_value(&block)
		Thread.new do
			loop do
				id, sensor, value = brutal_wait_for(/^\d+ SENS/).scan(/\d+/)
				yield(id.to_i, sensor.to_i, value.to_i)
			end
		end
	end
	
	private
	
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
		ensure
			@wait_for.delete(pattern)
		end
	end
	
	def brutal_wait_for (pattern)
		i = 0
		rd, wr = IO.pipe
		@wait_for[pattern] = wr
		ans = rd.read
		@wait_for.delete(pattern)
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


