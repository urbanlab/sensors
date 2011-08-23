require 'sense/common'
require 'logger'

module Sense
	# Contain methods userful for the demon : multiplexer's registration and dynamic callbacks of clients' messages
	# TODO : réorganiser private/... solidifier réception message
	class Daemon
		include Sense::Common
	
		# Initialization of the client.
		#@param [Integer] network The identifier of the network the demon will work on.
		#@param [String] host The adress of the machine where Redis is running
		#@param [Integer] port Port where Redis listen
		#@param [Logger] logger An optional Logger to write redis related events.
		#
		def initialize(network, host = 'localhost', port = 6379, logger = Logger.new(nil))
			load(network, host, port)
			@redis_listener = Redis.new host: host, port: port, thread_safe: false
			@log = logger
		end
	
		# Destroy the entire database and configuration
		#
		def flushdb
			@redis.flushdb
			@log.info("Flushing database")
		end
	
		# Clean up a multiplexer's sensors and actuators
		# @param [Integer] multi_id Id of the multi to be cleaned
		# TODO :test
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
			config[:id] = multi_id
			@redis.hset(path(), multi_id, config.to_json)
			@log.debug("Registering multiplexer's configuration : #{config}")
		end
	
		# Publish a sensor's value
		#@return true if the value was succefully published. false with log otherwise
		#
		def publish_value(multi_id, sensor, raw_value)
			return false unless knows? :sensor, multi_id, sensor
			path = path(:sensor, :value, multi_id, sensor)
			config = get_config(:sensor, multi_id, sensor)
			if config == nil
				@log.error("Tried to publish a value from an unknown multiplexer : #{multi_id}")
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
			@redis.mapped_hmset(path, key)
			@redis.publish(path, key.to_json) #TODO ne publier que la valeur ?
			@redis.publish(path(:sensor, :raw_value, multi_id, sensor), value)
			return true
		end
	
		# Register a sensor
		#
		def register_device msgid, type, config
			multi = config.delete(:multiplexer)
			if (not multi.is_a? Integer) or (not knows_multi? multi)
				@log.warn("A client tried to add a #{type} with a bad multiplexer id : #{multi}")
				answer(msgid, false, "bad multiplexer id")
				return
			end
			multi_config = get_multi_config multi
			if not multi_config
				@log.warn("A client tried to add a #{type} with an unknown multiplexer : #{multi}")
				answer(msgid, false, "unknown multiplexer")
				return
			end
			must_take = false
			case multi_config[:network]
				when 0
					must_take = true
				when @network
					# rien à faire ?
				else
					@log.warn("A client tried to add a #{type} that belong to another network : #{multi_config[:network]}")
					answer(msgid, false, "multiplexer belong to network #{multi_config[:networ]}")
					return
			end
			profile = get_profile type, config[:profile]
			if profile == nil
				@log.warn("A client tried to add a #{type} with an unknown profile : #{config[:profile]} (multiplexer : #{multi})")
				answer(msgid, false, "unknown profile")
				return
			end
			begin
				config.must_have(CONFIG[type][:necessary])
				config.can_have(CONFIG[type][:optional])
				profile.must_have(PROFILE[type][:necessary])
				profile.can_have(PROFILE[type][:optional])
			rescue ArgumentError => error
				@log.warn("A client tried to add a bad sensor config or profile : #{error.message}")
				answer(msgid, false, "Incomplete config or profile : #{error.message}")
				return
			end
			period = config[:period] || profile[:period]
			if not period #TODO : allow non looping sensors ?
				@log.warn("A client tried to add the sensor #{multi}:#{config[:pin]} without period. Config : #{config}, profile : #{profile}")
				answer(msgid, false, "Period is missing in profile and config")
				return
			end
			pin = config.delete(:pin)
			method = {actuator: @on_new_actuator, sensor: @on_new_sensor}[type]
			if method and method.call(multi, pin, profile[:function], period, *[profile[:option1], profile[:option2]])
				if must_take
					multi_config[:network] = @network
					set_multi_config multi, multi_config
				end
				@redis.hset(path(type, :config, multi), pin, config.to_json)
				answer(msgid, true)
			else
				#@redis.publish("#{PREFIX}.#{message-id}", "KO") if message-id
				answer(msgid, false, "Refused by multi, or multi disconnected")
			end
		end
	
		# Unregister a device
		#
		def unregister_device msgid, config
			if (not config[:multiplexer].is_a? Integer)
				@log.warn("A client tried to delete a #{type} with bad multiplexer id : #{parse[:multiplexer]}")
				answer(msgid, false, "Bad multiplexer id")
				return
			end
			if (not config[:pin].is_a? Integer)
				@log.warn("A client tried to delete a #{type} with bad pin : #{pin}")
				answer(msgid, false, "Bad id")
				return
			end
			if not knows?(config[:type], config[:multiplexer], config[:pin])
				@log.warn("A client tried to delete an unknown #{config[:type]} : #{config[:multiplexer]}:pin")
				answer(msgid, false, "unknown #{config[:type]} or multiplexer")
				return
			end
			callback = {sensor: @on_deleted_sensor, actuator: @on_deleted_actuator}[config[:type].intern]
			if callback && callback.call(config[:multiplexer], config[:pin])
				@redis.del(path(config[:type], :value, config[:multiplexer], config[:pin]))
				@redis.hdel(path(config[:type], :config, config[:multiplexer]), config[:pin])
				answer(msgid, true)
			else
				answer(msgid, false, "Refused by multiplexer or multiplexer did not answer")
			end
		end
	
		# Callback when a client request to add a sensor
		#@yield [multi_id, pin, function, period, *[option1, option2]] Block will be called when a client request a new sensor with client's parameters
		#@yieldreturn True if the new sensor is accepted, False if not
		#
		def on_new_sensor &block
			@on_new_sensor = block
		end
	
		# Callback when a client request to add an actu
		#
		def on_new_actuator &block
			@on_new_actuator = block
		end
	
		# Callback when a client request to delete a sensor
		#@yield [multi_id, pin] Action to do when a client request to delete a device on a pin of the multiplexer multi_id
		#@yieldreturn True if the destruction was accepted
		#
		def on_deleted_sensor(&block)
			@on_deleted_sensor = block
		end
	
		def on_deleted_actuator(&block)
			@on_deleted_actuator = block
		end
	
		def on_actuator_state(&block)
			@on_actuator_state = block
		end

		def take_callback idmsg, id_multi
			if not id_multi.is_a? Integer
				@log.warn("A client tried to take a multiplexer with bad multi_id or network")
				answer(idmsg, false, "bad multiplexer id or network")
				return
			end
			if @on_taken && @on_taken.call(id_multi)
				config = get_multi_config(id_multi)	#TODO : vérifier ça avant le call
				clean_up(id_multi)
				config[:network] = @network
				set_multi_config(id_multi, config)
				answer(idmsg, true)
			else
				answer(idmsg, false, "Failed to reset the multiplexer.")
			end
		end
	
		# Callback when a client request to take a sensor
		#@yield [id_multi, network]
		#
		def on_taken &block
			@on_taken = block
		end
	
		def actuator_state_callback msgid, message
			if not message[:multiplexer].is_a? Integer
				@log.warn("A client tried to change the state of an invalid multiplexer")
				answer(msgid, false, "Muliplexer id is invalid")
				return
			end
			if not (message[:state] == 0 or message[:state] == 1)
				@log.warn("A client requested a bad state for a multiplexer")
				answer(msgid, false, "bad state")
				return
			end
			if not mine? message[:multiplexer]
				@log.warn("A client tried to change the state of an unknown multi")
				answer(msgid, false, "unknown multi")
				return
			end
			if not knows? :actuator, message[:multiplexer], message[:pin]
				@log.warn("A client tried to change the state of an unknown actu")
				answer(msgid, false, "unknown actu")
				return
			end
			if @on_actuator_state && @on_actuator_state.call(message[:multiplexer], message[:pin], message[:state])
				answer(msgid, true)
			else
				answer(msgid, false, "the multiplexer did not answer or refused")
			end
		end

		# Read the messages and call the callbacks
		# message : "JSON"
		#
		def process_messages
			while true
				begin
					message = JSON.parse(@redis_listener.blpop("#{PREFIX}.network:#{@network}.messages", 0)[1])
				rescue JSON::JSONError => e
					@log.warn("A client sent an invalid message")
					next
				end
				message.recursive_symbolize_keys!
				begin
					message.must_have(command: String, message: Object)
					message.can_have(id: Integer)
				rescue ArgumentError => e
					@log.warn("A client sent an invalid message.")
					answer(message[:id], false, e.message)
					next
				end
				msgid = message.delete(:id)
				command = message.delete(:command) # TODO check si c'est un hash quand ça doit en être un
				args = message.delete(:message)
				case command
					when "add_sensor"
						register_device msgid, :sensor, args
					when "add_actuator"
						register_device msgid, :actuator, args
					when "delete"
						unregister_device msgid, args
					when "take"
						take_callback msgid, args
					when "actuator_state"
						actuator_state_callback msgid, args
					else
						@log.warn("A client sent an unknown command : \"#{command}\"")
						answer(msgid, false, "Unknown command \"#{command}\"")
				end
			end
		end
	
		private
		# Answer a message
		#
		def answer(id, ok, message=nil)
			ok = {true => "OK", false => "KO"}[ok]
			answer = "#{ok}"
			answer << "::#{message}" if message
			@redis.lpush("#{PREFIX}.#{id}", answer) if id
			@redis.expire("#{PREFIX}.#{id}", 60) if id
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
					else
						raise TypeError, "Bad rpn" unless e.is_numeric?
						stack.push(e.to_f)
				end
			end
			stack[0]
		end
	end
end

