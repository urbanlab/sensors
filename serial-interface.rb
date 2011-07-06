require 'rubygems'
require 'serialport'
require 'timeout'
require 'thread'
require 'io/wait'

CMD = { :list => "l", :add => "a", :remove => "d", :tasks => "t" , :id => "i" }
ANS = { :sensor => "SENS", :new => "NEW", :implementations => "LIST", :tasks => "TASKS" , :ok => "OK"}
#TODO verify the execution of add, id and remove
class Serial_interface
	attr_accessor :thr
	def initialize port, baudrate, timeout = 1, retry_nb = 3
		@serial = SerialPort.new port, baudrate
		@values_callback = []
		@news_callback = []
		@list = []
		@tasks = []
		@oks = []
		@timeout = timeout
		@retry = retry_nb
		Thread.abort_on_exception = true
		listener = Thread.new {
			process_messages
		}
	end
	
	def process_messages
		loop do
			buff = ""
			while not buff.end_with?("\r\n")
				@serial.wait
				buff << @serial.readline
			end
			id_multi, command, *args = buff.delete("\r\n").split("\s")
			#p id_multi, command, *args
			if (id_multi and id_multi.is_integer?)
				id_multi = id_multi.to_i
				case command
					when ANS[:sensor]
						@values_callback.each { |cb| cb.call id_multi, args[0].to_i, args[1].to_i }
					when ANS[:implementations]
						@list[id_multi].push(args) if @list[id_multi]
					when ANS[:tasks]
						@tasks[id_multi].push(Hash[*args.join(" ").scan(/\w+/).collect {|i| (i.is_integer?)? i.to_i : i}]) if @tasks[id_multi]
					when ANS[:oks]
						@oks[id_multi].push(id_multi) if @oks[id_multi]
					when ANS[:new]
						@news_callback.each { |cb| cb.call id_multi }
					else
						#puts "ignored command #{id_multi} #{command}"
				end
			end
		end
	end
	
	def snd_message(multi, command, *args)
		message = "#{multi} #{CMD[command]} #{args.join(" ")}\n"
		@serial.write(message)
	end
	
	
	def add_task(multi, pin, task)
		snd_message(multi, :add, task["function"], task["period"], pin)
	end
	
	def rem_task(multi, pin)
		snd_message(multi, :remove, pin)
	end
	
	def change_id(old, new)
		snd_message(old, :id, new)
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
		@list[multi] = Queue.new
		snd_message(multi, :list)
		timeout_try(@list[multi])
	end
	
	def list_tasks(multi)
		@tasks[multi] = Queue.new
		snd_message(multi, :tasks)
		timeout_try(@tasks[multi])
	end
	
	# block has 1 int argument : multiplexer's id.
	def on_new_multi(&block)
		@news_callback.push(block)
	end
	
	# block has 3 int arguments : the multiplexer's id, pin number and value.
	def on_sensor_value(&block)
		@values_callback.push(block)
	end
end

class String
  def is_integer?
    begin Integer(self) ; true end rescue false
  end
end


=begin
serial = Serial_interface.new('/dev/ttyUSB0', 19200)
serial.on_sensor_value do |multi, sensor, value|
	puts "got a value by #{multi} on #{sensor} of #{value}"
end

serial.on_new_multi do |id|
	imp = serial.list_implementations(id)
	tasks = serial.list_tasks(id)
	puts "new multi : #{id}"
	p imp
	p tasks
	serial.add_task(id, 14, {"function" => "ain", "period" => 1000})
end

loop do
	sleep 5
	p "alive"
end
=end

