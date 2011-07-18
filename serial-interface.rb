require 'rubygems'
require 'serialport'
require 'timeout'
require 'thread'
require 'io/wait'

CMD = { :list => "l", :add => "a", :remove => "d", :tasks => "t" , :id => "i", :reset => "r" }
ANS = { :sensor => "SENS", :new => "NEW", :implementations => "LIST", :tasks => "TASKS" , :ok => "OK", :add => "ADD", :remove => "DEL"}
#TODO verify the execution of add, id and remove
class Serial_interface
	def initialize port, baudrate, timeout = 1, retry_nb = 3
		@serial = SerialPort.new port, baudrate
		@wait_for = {} # {pattern => wpipe}
		@timeout = timeout
		@retry = retry_nb
		# Thread.abort_on_exception = true
		listener = Thread.new {
			process_messages
		}
	end
	
	def process_messages
		loop do
			buff = ""
			while not buff.end_with?("\r\n")
				@serial.wait
				buff << @serial.gets
			end
			p buff
			@wait_for.each do |pattern, pipe|
				if (buff.match(pattern))
					pipe.write(buff)
					pipe.close
				end
			end
		end
	end
	
	def reset(multi)
		snd_message(multi, :reset)
		wait_for(/^#{multi} RST/)
	end
	
	def add_task(multi, pin, function, period, *args)
		args.delete nil
		snd_message(multi, :add, function, period, pin, *args)
		wait_for(/^#{multi} ADD #{pin}/) == "KO" ? false : true
	end
	
	def rem_task(multi, pin)
		snd_message(multi, :remove, pin)
		wait_for(/^#{multi} DEL #{pin}/) == "KO" ? false : true
	end
	
	def change_id(old, new)
		snd_message(old, :id, new)
		wait_for(/^#{new} ID/)
		#TODO : register
	end
	
	def timeout_try(queue)
		i = 0
		begin
			Timeout.timeout(@timeout){queue.pop}
		rescue Timeout::Error => e
			((i+=1) < @retry)? retry : raise(e)
		end
	end
	
	def list_implementations(multi)
		snd_message(multi, :list)
		wait_for(/^#{multi} LIST/).scan(/\w+/)
	end
	
	def list_tasks(multi)
		snd_message(multi, :tasks)
		ans = wait_for(/^#{multi} TASKS/)
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
	
	def snd_message(multi, command, *args)
		p multi, command, args
		msg = "#{multi} #{CMD[command]} #{args.join(" ")}".chomp(" ") + "\n"
		p msg
		@serial.write msg
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


