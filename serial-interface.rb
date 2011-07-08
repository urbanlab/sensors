require 'rubygems'
require 'serialport'
require 'timeout'
require 'thread'
require 'io/wait'

CMD = { :list => "l", :add => "a", :remove => "d", :tasks => "t" , :id => "i" }
ANS = { :sensor => "SENS", :new => "NEW", :implementations => "LIST", :tasks => "TASKS" , :ok => "OK"}
#TODO verify the execution of add, id and remove
class Serial_interface
	def initialize port, baudrate, timeout = 1, retry_nb = 3
		@serial = SerialPort.new port, baudrate
#		@values_callback = []
#		@news_callback = []
		@values = Queue.new
		@news = Queue.new
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
				buff << @serial.gets
			end
			id_multi, command, *args = buff.delete("\r\n").split("\s")
			#p id_multi, command, *args
			if (id_multi and id_multi.is_integer?)
				id_multi = id_multi.to_i
				case command
					when ANS[:sensor]
						@values.push({:multi => id_multi, :sensor => args[0].to_i, :value => args[1].to_i})
#						@values_callback.each { |cb| Thread.new(cb.call id_multi, args[0].to_i, args[1].to_i) }
					when ANS[:implementations]
						@list[id_multi].push(args) if @list[id_multi]
					when ANS[:tasks]
						@tasks[id_multi].push(Hash[*args.join(" ").scan(/\w+/).collect {|i| (i.is_integer?)? i.to_i : i}]) if @tasks[id_multi]
					when ANS[:oks]
						@oks[id_multi].push(id_multi) if @oks[id_multi]
					when ANS[:new]
						@news.push(id_multi)
#						@news_callback.each { |cb| Thread.new(cb.call id_multi) }
					else
						#puts "ignored command #{buff}"
				end
			end
		end
	end
	
	def snd_message(multi, command, *args)
		message = "#{multi} #{CMD[command]} #{args.join(" ")}\n"
		@serial.write(message)
	end
	
	
	def add_task(multi, pin, function, period)
		snd_message(multi, :add, function, period, pin)
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
		Thread.new do
			loop do
				id = @news.pop
				yield(id)
			end
		end

		#@news_callback.push(block)
	end
	
	# block has 3 int arguments : the multiplexer's id, pin number and value.
	def on_sensor_value(&block)
		Thread.new do
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


