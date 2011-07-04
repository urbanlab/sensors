require 'rubygems'
require 'json'
require 'redis-interface.rb'
=begin
- multiplexer : {"description" => "bla", "supported" => ["ain", "din"]}
Sur network:<network>:multiplexers = hash(multipl-id, objet multiplexer)

- sensor : {"description" => "verbose", "function" => "din", "period" => 1000, "unit" => "°C", "rpn" => "X 7 *"}
Sur network:<network>:multiplexers:<multipl-id>:sensors = hash (pin, objet sensor)

- actuator : {"pin" => 13, "fonction" => "bli"}
Sur network:<network>:multiplexers:<multipl-id>:actuators = hash (pin, objet actuator)

=end
class Client
	include Redis_interface
	def initialize
		r_start_interface('localhost', 6379, 1)
	end
	
	def snd
		r_set_sens_config(1, 14, {"description" => "temperature", "function" => "ain", "period" => 3000, "unit" => "Volt", "rpn" => "X"})
	end
end

cli = Client.new
cli.snd

