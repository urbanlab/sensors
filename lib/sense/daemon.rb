# -*- coding: utf-8 -*-
require 'sense/common'
require 'logger'

module Sense
	# Contain methods userful for the daemon : multiplexer's registration and dynamic callbacks of clients' messages
	# Use it to implement a new daemon
	#
	class Daemon
		include Sense::Common
	
		# Initialization of the client.
		# @param [Integer] network The identifier of the network the demon will work on.
		# @param [String] host The adress of the machine where Redis is running
		# @param [Integer] port Port where Redis listen
		# @param [Logger] logger An optional Logger to write redis related events.
		#
		def initialize(network, host = 'localhost', port = 6379, logger = Logger.new(nil))
			load(network, host, port)
			@redis_listener = Redis.new host: host, port: port, thread_safe: false
			@log = logger
			@failed_cmds = Array.new(10)
		end
	
		# Destroy the entire database and configuration
		#
		def flushdb
			@redis.flushdb
			@log.info("Flushing database")
		end
	
		# Clean up a multiplexer's sensors and actuators
		# @param [Integer] multi_id Id of the multi to be cleaned
		#
		def clean_up(multi_id)
			net = get_multi_config(multi_id)[:network]
			@redis.del(network_path(net, :sensor, :value, multi_id))
			@redis.del(network_path(net, :actuator, :value, multi_id))
			@redis.del(network_path(net, :sensor, :config, multi_id))
			@redis.del(network_path(net, :actuator, :config, multi_id))
		end

		# Assign a config to a multiplexer
		#
		def set_multi_config multi_id, config
			@redis.hset(path(), multi_id, config.to_json)
			@log.debug("Registering multiplexer's configuration : #{config}")
		end
		
		# Get an unassigned id
		# @return [Integer] the id
		#
		def get_unassigned_id
			ids = @redis.hkeys(path()).inject([]){|a,i|a << i.to_i}
			(Array(1..255) - ids)[0]
		end
	
		# Publish a sensor's value
		# @return true if the value was succefully published. false with log otherwise
		# @param [Integer] multi_id Id of the multiplexer that got the value
		# @param [Integer] sensor Pin of the sensor
		# @param [Integer] raw_value unormalized value
		#
		def publish_value(multi_id, sensor, raw_value)
			return false unless knows? :sensor, multi_id, sensor
			path = path(:sensor, :value, multi_id, sensor)
			config = get_config(:sensor, multi_id, sensor)
			if config == nil
				@log.warn("Tried to publish a value from an unknown multiplexer : #{multi_id}")
				return false
			end
			profile = get_profile(:sensor, config[:profile])
			if profile == nil
				@log.error("Tried to publish a value from an unknown profile : #{config[:profile]} (multiplexer : #{multi_id})")
				return false
			end
			if profile[:rpn].is_a? String
				rpn = profile[:rpn].sub("X", raw_value.to_s)
				begin
					value = solve_rpn(rpn)
				rescue Exception => e
					@log.error("Tried to publish a value with an icorrect rpn : #{profile[:rpn]} from #{config[:profile]}. Error : #{e.message}")
					return false
				end
			else
				value = raw_value
			end
			if profile[:precision].is_a? Integer
				value = value.round profile[:precision]
			end
			key = {value: value, timestamp: Time.now.to_f, unit: profile[:unit], name: config[:name]}
			old_value, set = @redis.multi do
				@redis.hget(path, "value")
				@redis.mapped_hmset(path, key)
				
			end
			old_value = old_value.to_f if old_value
			if (old_value) && (old_value != key[:value])
				@redis.publish(path(:sensor, :raw_value, multi_id, sensor), value)
				@redis.publish(path, key.to_json)
			end
			return true
		end
	
		# Callback when a client request to add a sensor
		# @yield [multi_id, pin, function, period, *[option1, option2]] Block will be called when a client request a new sensor with client's parameters
		# @yieldreturn True if the new sensor is accepted, False if not, nil if nobody answered
		#
		def on_new_sensor &block
			@on_new_sensor = block
		end
	
		# Callback when a client request to add an actu
		# @yield [multi_id, pin, function, period, *[option1, option2]] Block will be called when a client request a new actuator with client's parameters
		# @yieldreturn True if the new actuator is accepted, False if not, nil if nobody answered
		#
		def on_new_actuator &block
			@on_new_actuator = block
		end
	
		# Callback when a client request to delete a sensor
		# @yield [multi_id, pin] Action to do when a client request to delete a device on a pin of the multiplexer multi_id
		# @yieldreturn True if the destruction was accepted, False if not, nil if nobody answered
		#
		def on_deleted_sensor(&block)
			@on_deleted_sensor = block
		end
		
		# Callback when a client request to delete an actuator
		# @yield [multi_id, pin] Action to do when a client request to delete a device on a pin of the multiplexer multi_id
		# @yieldreturn True if the destruction was accepted, False if not, nil if nobody answered
		#
		def on_deleted_actuator(&block)
			@on_deleted_actuator = block
		end
		
		# Callback when a client request to change the state of an actuator
		# @yield [multi_id, pin, value] Action to change the state of an actuator
		# @yieldreturn True if it was a sucess, False if not, nil if nobody answered
		#
		def on_actuator_state(&block)
			@on_actuator_state = block
		end
	
		# Callback when a client request to take a sensor
		# @yield [id_multi, network]
		# @yieldreturn True if it was taken, False if not, nil if nobody answered
		#
		def on_taken &block
			@on_taken = block
		end

		# Read the messages from the client and call the callbacks
		#
		def process_messages
			loop do
				chan, message = @redis_listener.blpop("#{PREFIX}.network:#{@network}.messages", 0)
				@log.debug("A client sent the message : #{message}")
				msgid, command, args = parse(message)
				unless command
					@log.warn("A client sent an invalid message.")
					next
				end
				if msgid && @failed_cmds.include?(msgid) # Every daemon tried to contact the multi (blpop act as first waiting, first served)
					answer(msgid, false, "No daemon could contact the multiplexer")
					next
				end
				ans, info = case command
					when "add_sensor"
						register_device :sensor, args
					when "add_actuator"
						register_device :actuator, args
					when "delete_sensor"
						unregister_device :sensor, args
					when "delete_actuator"
						unregister_device :actuator, args
					when "take"
						take_callback args
					when "actuator_state"
						actuator_state_callback args
					else
						@log.warn("A client sent an unknown command : \"#{command}\"")
						[false, "Unknown command \"#{command}\""]
				end
				case ans
					when true  # Success
						answer(msgid, true)
					when false # Failure
						answer(msgid, false, info)
					else       # Timeout error, transmit to another daemon
						if not msgid			   # Generate an id only for daemons
							msgid = rand.hash.abs
							message = "#{msgid}:#{message}"
						end
						@failed_cmds.push(msgid).unshift
						#answer(msgid, false, "wait") # TODO utile ?
						@redis_listener.lpush("#{PREFIX}.network:#@network.messages", message) #TODO generate with path?
				end
			end
		end
	
		private
		# Parse an incoming message
		#
		def parse message
			return nil unless message.valid_encoding?
			message = message.dup
			prefix = message.slice!(/\S+/)
			return nil unless prefix
			id, command = prefix.scan(/(\d+:)?(\w+)/).flatten
			id = id.delete(":").to_i if id
			id = nil if id == 0
			if message.include?(':')
				message = Hash[*message.scan(/(\w+):([^:\s]+)/).flatten].symbolize_keys if message.include?(':')
				message.each_key {|k| message[k] = message[k].to_i if message[k].is_numeric?}
			else
				message.delete!(' ')
			end
			return [id, command, message]
		end
		
		# Answer a message
		#
		def answer(id, ok, message=nil)
			ok = {true => "OK", false => "KO"}[ok]
			answer = "#{ok}"
			answer << "::#{message}" if message
			@redis.lpush("#{PREFIX}.#{id}", answer) if id
			@redis.expire("#{PREFIX}.#{id}", 60) if id
		end

		# Call the callback when a client request to change the state of an actu
		#
		def actuator_state_callback message
			if not message.is_a? Hash
				@log.warn("A client tried to change the state of an actuator with an invalid message")
				return false, "invalid message"
			end
			if not (message[:multiplexer].is_a? Integer or message[:multiplexer].is_a? String)
				@log.warn("A client tried to change the state of an invalid multiplexer")
				return false, "Muliplexer id is invalid"
			end
			multi_id = get_multi_id(message[:multiplexer])
			pin = get_pin(:actuator, multi_id, message[:pin])
			if not (message[:state] == 0 or message[:state] == 1)
				@log.warn("A client requested a bad state for a multiplexer")
				return false, "bad state"
			end
			if not mine? multi_id
				@log.warn("A client tried to change the state of an unknown multi")
				return false, "unknown multi"
			end
			if not knows? :actuator, multi_id, pin
				@log.warn("A client tried to change the state of an unknown actu")
				return false, "unknown actu"
			end
			return [false, "unimplemented method"] unless @on_actuator_state
			case @on_actuator_state.call(multi_id, pin, message[:state])
				when true
					@log.info("Switched #{message[:state] == 1 ? "on" : "off"} #{multi_id}:#{pin}")
					return true
				when false
					return false, "the multiplexer refused"
				else
					return nil
			end
		end
		
		# Call the on_taken callback
		#
		def take_callback multi
			return false, "invalid multiplexer" unless multi.is_a? String
			multi = multi.to_i if multi.is_integer?
			id_multi = get_multi_id(multi)
			if not id_multi.is_a? Integer
				@log.warn("A client tried to take a multiplexer with bad multi_id or network")
				return false, "bad multiplexer id or network"
			end
			config = get_multi_config(id_multi)
			if not config.is_a? Hash
				@log.warn("A client tried to take an unknown multiplexer")
				return false, "unknown multiplexer"
			end
			return false, "unimplemented method" unless @on_taken
			case @on_taken.call(id_multi)
				when true
					clean_up(id_multi)
					config[:network] = @network
					@log.info("Associated #{id_multi}")
					set_multi_config(id_multi, config)
					return true
				when false
					return false, "Failed to reset the multiplexer"
				else
					return nil
			end
		end
		
		# Call the callback to register a sensor
		#
		def register_device type, config
			if not config.is_a? Hash
				@log.warn("A client tried to add a #{type} with a bad message")
				return false, "bad message"
			end
			multi = config.delete(:multiplexer)
			multi_id = get_multi_id(multi)
			if (not multi_id.is_a? Integer)
				@log.warn("A client tried to add a #{type} with a bad multiplexer id : #{multi}")
				return false, "bad multiplexer id"
			end
			multi_config = get_multi_config multi_id
			if not multi_config
				@log.warn("A client tried to add a #{type} with an unknown multiplexer : #{multi}")
				return false, "unknown multiplexer"
			end
			must_take = false
			case multi_config[:network]
				when 0
					must_take = true
				when @network
					# rien à faire ?
				else
					@log.warn("A client tried to add a #{type} that belong to another network : #{multi_config[:network]}")
					return false, "multiplexer belong to network #{multi_config[:network]}"
			end
			profile = get_profile type, config[:profile]
			if profile == nil
				@log.warn("A client tried to add a #{type} with an unknown profile : #{config[:profile]} (multiplexer : #{multi})")
				return false, "unknown profile"
			end
			begin
				config.must_have(CONFIG[type][:necessary])
				config.can_have(CONFIG[type][:optional])
			rescue ArgumentError => error
				@log.warn("A client tried to add a bad sensor config or profile : #{error.message}")
				return false, "Incomplete config : #{error.message}"
			end
			begin
				profile.must_have(PROFILE[type][:necessary])
				profile.can_have(PROFILE[type][:optional])
			rescue ArgumentError => error
				@log.error("The profile #{config[:profile]} is bad : #{error.message}")
				return false, "The profile exists but is invalid : #{error.message}"
			end
			period = config[:period] || profile[:period]
			if not period #TODO : allow non looping sensors ?
				@log.warn("A client tried to add the sensor #{multi}:#{config[:pin]} without period. Config : #{config}, profile : #{profile}")
				return false, "Period is missing in profile and config"
			end
			pin = config.delete(:pin)
			method = {actuator: @on_new_actuator, sensor: @on_new_sensor}[type]
			return [false, "unimplemented command"] unless method
			case method.call(multi_id, pin, profile[:function], period, *[profile[:option1], profile[:option2]])
				when true
					if must_take
						multi_config[:network] = @network
						set_multi_config multi_id, multi_config
					end
					@log.info("Add a #{type} on #{multi_id}:#{pin}")
					@redis.hset(path(type, :config, multi_id), pin, config.to_json)
					return true
				when false
					return false, "Refused by multi"
				else
					return nil
			end
		end
	
		# Call the callback to unregister a device
		#
		def unregister_device type, config
			if not (config.is_a? Hash)
				@log.warn("A client tried to delete a #{type} with an invalid message")
				return false, "Bad message"
			end
			if not (config[:multiplexer].is_a? Integer or config[:multiplexer].is_a? String)
				@log.warn("A client tried to delete a #{type} with bad multiplexer id : #{config[:multiplexer]}")
				return false, "Bad multiplexer id"
			end
			if not (config[:pin].is_a? Integer or config[:pin].is_a? String)
				@log.warn("A client tried to delete a #{type} with bad pin : #{config[:pin]}")
				return false, "Bad id"
			end
			multi_id = get_multi_id(config[:multiplexer])
			pin = get_pin(type, multi_id, config[:pin])
			if not knows?(type, multi_id, pin)
				@log.warn("A client tried to delete an unknown #{type} : #{config[:multiplexer]}:#{config[:pin]}")
				return false, "unknown #{type} or multiplexer"
			end
			callback = {sensor: @on_deleted_sensor, actuator: @on_deleted_actuator}[type]
			return [false, "unimplemented command"] unless callback
			case callback.call(multi_id, pin)
				when true
					@redis.del(path(type, :value, multi_id, pin))
					@redis.hdel(path(type, :config, multi_id), pin)
					@log.info("Deleted a #{type} from #{multi_id}:#{pin}")
					return true
				when false
					return false, "Refused by multiplexer"
				when nil
					return nil
			end
		end

		# Solve a Reverse Polish Notation
		#
		def solve_rpn(s)
			stack = []
			s.split("\s").each do |e|
				case e
					when "+"
						stack.push(stack.pop + stack.pop)
					when "-"
						stack.push(-stack.pop + stack.pop)
					when "*"
						stack.push(stack.pop * stack.pop)
					when "/"
						a, b = stack.pop, stack.pop
						stack.push(b / a)
          when "<?"
            a, b = stack.pop, stack.pop
            stack.push(b < a ? 1 : 0)
          when ">?"
            a, b = stack.pop, stack.pop
            stack.push(b > a ? 1 : 0)
          when "<=?"
            a, b = stack.pop, stack.pop
            stack.push(b <= a ? 1 : 0)
          when ">=?"
            a, b = stack.pop, stack.pop
            stack.push(b >= a ? 1 : 0)
					else
						raise TypeError, "Bad rpn" unless e.is_numeric?
						stack.push(e.to_f)
				end
			end
			stack[0]
		end
	end
end


