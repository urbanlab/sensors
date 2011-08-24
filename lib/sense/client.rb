require 'sense/common'

module Sense
	# Contain useful methods for the client : writing sensors' configuration, reading published values...
	#
	class Client
		include Sense::Common
		def initialize(network, host = 'localhost', port = 6379)
			@id = 0
			load(network, host, port)
		end
	
		# Return the list of supported profile from a list of arduino functions
		# @return [Array<String>] the profiles
		#
		def support(functions)
			list_profiles(:actuator).merge(list_profiles(:sensor)).select { |name, profile|
				functions.include? profile[:function]
			}.keys
		end
	
		# Register description of a multiplexer.
		# @return [boolean] true if the description was succefully changed
		#
		#
		def set_description multi_id, description
			raise ArgumentError "Description must be a string" unless description.is_a?(String)
			return false unless knows_multi?(multi_id)
			config = JSON.s_parse(@redis.hget(path(), multi_id))
			config[:description] = description
			@redis.hset(path(), multi_id, config.to_json)
			return true
		end
	
		# Associate a multi to the network
		# @param [Integer] multi_id Id of the multi
		#
		def take multi_id
			send("take", multi_id)
		end
	
		# Register a sensor or an actuator.
		# @return [boolean] true if a demon was listening
		# @option config [String] :name Name of the device
		# @option config [String] :profile Profile associated to the device
		# @option config [Integer] :period Sensor only : Period beetween to sensor reading (in ms) (optional if the profile has a default period)
		# @option config [Integer, optional] :value Actuator only : Initial value
		# @option config [Integer] :pin Pin where the device is plugged
		# @param [Integer] multi_id Multiplexer's Id
		# @param [Symbol] type Device type, can be :sensor or :actuator
		#
		def add type, multi_id, config = {}
			config[:multiplexer] = multi_id
			send("add_#{type}", config)
		end
	
		# Unregister a sensor
		# @param [Symbol] type Device type, can be :sensor or :actuator
		# @param [Integer] multi_id Id of the multiplexer
		# @param [Integer] pin Pin where the device was plugged
		# @return [boolean] true if a demon was listening
		#
		def remove type, multi_id, pin
			opts = {type: type, multiplexer: multi_id, pin: pin}
			send("delete", opts)
		end
	
		
		# Activate or deactivate an actuator
		#
		def set_actuator_state(multi_id, pin, state)
			send("actuator_state", {multiplexer: multi_id, state: state, pin: pin})
		end
	
		# Register a sensor profile
		# @param [Symbol] type Profile type, can be :sensor or :actuator
		# @param [String] name Profile name
		# @option profile [String] :function Arduino's function the profile uses
		# @option profile [Integer, optional] :period default period
		# @option profile [Integer, optional] :option1 first function's argument (see its description)
		# @option profile [Integer, optional] :option2 second function's argument (see its description)
		# @option profile [String] :unit unit of the sensor's value (sensor only)
		# @option profile [String, optional] :rpn optional RPN transformation to apply to raw value (sensor only)
		# @option profile [Integer, optional] :precision optional precision of the sensor (eg. 3 for value like 334.411, -1 for value like 330)
		#
		def add_profile( type, name, profile = {} )
			raise ArgumentError, "Name should be a String" unless name.is_a? String
			raise(ArgumentError, "type should be :actuator or :sensor") unless (type == :actuator or type == :sensor)
			profile.must_have(PROFILE[type][:necessary])
			profile.can_have(PROFILE[type][:optional])
			@redis.hset(path(type), name, profile.to_json)
		end
	
		# Unregister a profile
		# @return true if something was removed
		#
		def remove_profile( type, name )
			@redis.hdel(path(type), name) == 1
		end
	
		# Callback when a value is published on redis.
		# @macro type
		# @param [String, Integer] multi id of the multiplexer you need to listen to, or '*' for all multiplexers
		# @param [String, Integer] pin Pin you need to listen to, or '*' for all the pins
		# @yield [multi_id, pin, value, unit, name] Processing of the published value for type = :sensor
		# @yield [multi_id, pin, value] Processing of the published value for type = :actuator
		#
		def on_published_value(type, multi = "*", pin = "*")
			Thread.new do
				redis = Redis.new host: @host, port: @port
				redis.psubscribe(path(type, :value, multi, pin)) do |on|
					on.pmessage do |pattern, channel, value|
						parse = Hash[ *channel.scan(/(\w+):(\w+)/).flatten ].symbolize_keys
						case type
							when :sensor
								parse.merge!(JSON.s_parse(value))
								yield parse[:multiplexer].to_i, parse[type].to_i, parse[:value].to_f, parse[:unit], parse[:name]
							when :actuator
								yield parse[:multiplexer].to_i, parse[type].to_i, value.to_i
						end
					end
				end
			end
		end
	
		private
	
		# Send a message and wait for the answer
		#
		def send(command, args)
			id_message = rand.hash.abs
			message = "#{id_message}:#{command}#{encode(args)}"
			@redis.lpush("#{PREFIX}.network:#@network.messages", message)
			chan, answer = @redis.blpop("#{PREFIX}.#{id_message}", 10)
			return [answer.split("::")[0] == "OK", answer.split("::")[1]]
		end
		
		# Encode a message
		#
		def encode message
			return " #{message}" unless message.is_a? Hash
			return message.inject("") {|s, k| s << " #{k[0]}:#{k[1]}"}
		end
	end
end

