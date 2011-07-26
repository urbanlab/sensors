require './redis-interface-client.rb'

cli = Redis_interface_client.new(1, 'localhost', 6379)
Thread.abort_on_exception = true
cli.on_published_value(:sensor) do |multi, pin, value|
	profile = cli.list_profiles(:sensor)[cli.get_config(:sensor, multi, pin)[:profile]]
	sensor_config = cli.get_config :sensor, multi, pin
	s = "#{multi} : #{sensor_config[:name]} - "
	s << case profile[:unit]
		when "boolean" then (value == 1)? "on" : "off"
		else "#{value.round(2)}#{profile[:unit]}"
	end
	puts s
end

sleep

