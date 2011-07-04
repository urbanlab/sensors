=begin
- multiplexer : {:description => "bla", :supported => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {:fonction => "din", :rpn => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {:pin => 13, :fonction => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end
require 'rubygems'
require 'redis'

PREFIX = "network"
MULTI  = "multiplexers"
SENS   = "sensors"
ACTU   = "actuators"
VALUE  = "value"
CONF   = "config"

module Redis_interface
	
	def r_start_interface host, port, network
		@redis = Redis.new :host => host, :port => port
		@network = network
		@prefix = "#{PREFIX}:#{@network}"
	end
	
	def r_get_multi_keys
		@redis.hkeys("#{@prefix}:#{MULTI}:#{CONF}")
	end
	
	def r_get_multi_config multi_id
		JSON.parse(@redis.hget("#{@prefix}:#{MULTI}:#{CONF}", multi_id))
	end
	
	def r_set_multi_config multi_id, config
		path = "#{@prefix}:#{MULTI}"
		@redis.hset("#{path}:#{CONF}", multi_id, config.to_json)
		@redis.publish("#{path}:#{multi_id}:#{CONF}", config.to_json)
	end
	
	def r_publish_value(multi_id, sensor, value)
		path = "#{@prefix}:#{MULTI}:#{multi_id}:#{SENS}"
		key = {"value" => value,"timestamp" => Time.now.to_i}.to_json
		@redis.hset("#{path}:#{VALUE}", sensor, key)
		@redis.publish("#{path}:#{sensor}:#{VALUE}", key)
	end
	
	def r_set_sens_config multi_id, pin, config
		path = "#{@prefix}:#{MULTI}:#{multi_id}:#{SENS}"
		@redis.hset("#{path}:#{CONF}", pin, config.to_json)
		@redis.publish("#{path}:#{pin}:#{CONF}", config.to_json)
	end

	def r_on_new_sensor(&block)
		redis.psubscribe(@prefix + @multi_path + ":*" + @sens_path + ":*:config") do |on|
			on.pmessage do |pattern, channel, message|
				yield JSON.parse(message)[0], JSON.parse(message)[1]
			end
		end
	end
end
