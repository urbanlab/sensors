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
module Redis_interface
	
	def r_start_interface host, port, network
		@redis = Redis.new :host => host, :port => port
		@network = network
		@prefix = "network:#{@network}"
		@multi_path = ":multiplexers"
		@sens_path = ":sensors"
		@actu_path = ":actuators"
	end
	
	def r_get_multi_keys
		@redis.hkeys(@prefix + @multi_path)
	end
	
	def r_get_multi_config multi_id
		JSON.parse(@redis.hget(@prefix + @multi_path, multi_id))
	end
	
	def r_set_multi_config multi_id, config
		@redis.hset(@prefix + @multi_path, multi_id, config.to_json)
	end
	
	def r_publish_value(multi_id, sensor, value)
		path = @prefix + @multi_path + ":" + multi_id.to_str + @sens_path
		key = [value, Time.now.to_i].to_json
		@redis.publish(path + ":" + sensor.to_str, key)
		@redis.hset(path, sensor, key)
	end
	
	def get_redis_path(multiplexer = false, sensor = false)
		path = "network:#{@network}"
		path << ":multiplexers:#{multiplexer}" if multiplexer
		path << ":sensors:#{sensor}" if sensor
		path
	end
end
