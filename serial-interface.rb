require 'rubygems'
require 'serialport'
require 'timeout'

CMD = { :list => "l", :add => "a", :remove => "d", :tasks => "t" , :id => "i" }
ANS = { :sensor => "SENS", :new => "NEW", :implementations => "LIST", :tasks => "TASKS" , :ok => "OK"}

class Serial_interface
	attr_accessor :thr
	def initialize port, baudrate, timeout = 5
		@serial = SerialPort.new port, baudrate
		@read_queue = Queue.new
		@values = Queue.new
		@list = []
		@tasks = []
		@oks = []
		@timeout = timeout
		Thread.abort_on_exception = true
		listener = Thread.new {
			process_messages
		}
	end
	
	def process_messages
		loop do
			id_multi, command, *args = @serial.readline.delete("\r\n").split("\s")
			if (id_multi and id_multi.is_integer?)
				id_multi = id_multi.to_i
				case command
					when ANS[:sensor]
						@values.push({:multi => id_multi, :sensor => args[0].to_i, :value => args[1].to_i})
					when ANS[:implementations]
						@list[id_multi].push(args) if @list[id_multi]
					when ANS[:tasks]
						@tasks[id_multi].push(Hash[*args.join(" ").scan(/\w+/).collect {|i| (i.is_integer?)? i.to_i : i}]) if @tasks[id_multi]
					when ANS[:oks]
						@oks[id_multi].push(id_multi) if @oks[id_multi]
					else
						puts "ignored command #{id_multi} #{command}"
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
	
	def list_implementations(multi)
		@list[multi] = Queue.new
		snd_message(multi, :list)
		Timeout::timeout(@timeout){@list[multi].pop}
	end
	
	def list_tasks(multi)
		@tasks[multi] = Queue.new
		snd_message(multi, :tasks)
		Timeout::timeout(@timeout){@tasks[multi].pop}
	end
	
	def on_sensor_value(&block)
		@thr = Thread.new do
			loop do
				message = @values.pop
				yield(message[:multi], message[:sensor], message[:value])
			end
		end
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
	p "got"
	p multi
	p sensor
	p value
end
p serial.list_implementations(1)
p serial.list_tasks(1)
serial.add_task(1, 14, {"function" => "1wi", "period" => 1000})
loop do
	sleep 1
	p "alive"
end
=end

