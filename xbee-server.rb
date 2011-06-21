#!/usr/bin/ruby -w

require 'rubygems'
require 'serialport'
require 'redis'

opts = ["/dev/ttyUSB0", 9600]
opts.each_index do |i|
	opts[i] = ARGV[i] if ARGV[i]
end

$Serial = SerialPort.new(*opts)
$Redis = Redis.new

loop do
	p "eof" if $Serial.eof?
	msg = $Serial.readline.split("\s")
	id = msg.shift
	$Redis.publish(id, msg.join(" "))
end
