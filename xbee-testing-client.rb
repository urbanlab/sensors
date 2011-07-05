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

cli = Redis_interface.new('localhost', 6379, 1)
#cli.set_sensor_config(3, 11, {"description" => "bouton", "function" => "din", "period" => 10, "unit" => "Bool", "rpn" => "X"})
cli.on_published_value do |multi, pin, valeur|
	p multi
	p pin
	p valeur
end

sleep

