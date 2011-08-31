require 'io/wait'
require 'serialport'

module Sense
	# Xbee's configuration tools
	#
	module Xbee
		# @param[String, SerialPort] device SerialPort or path to configure
		# @param[Symbol] type :daemon or :arduino
		# @param[Boolean] verbose print what it sends and get
		#
		def self.setup(device, type, verbose = false, baudrate = 9600)
			@s = nil
			@v = verbose
			answers = []
			opts = case type
				when :daemon
					{ID: 3666, BD: 3, MY: 0, DL: 1, DH: 0}
				when :arduino
					{ID: 3666, BD: 3, MY: 1, DL: 0, DH: 0}
			end
			
			begin
				if device.is_a? String
					@s = SerialPort.new device, baudrate
				elsif device.is_a? File or device.is_a? SerialPort
					@s = device
				else
					return false
				end
				return false unless send_message('+++') == "OK\r"
				send_message("ATRE\r")
				opts.each do |k, v|
					send_message("AT#{k} #{v}\r")
				end
				send_message("ATWR\r")
				send_message("ATCN\r")
				return true
			rescue Errno, IOError => e
				puts e if verbose
				return false
			ensure
				@s.close if device.is_a?(String) && @s.is_a?(File)
			end
		end
		
		private
		# @param[String] message
		# @return[String] answer
		#
		def self.send_message message
			ans = false
			try = 0
			while not ans
				puts ">#{message}" if @v
				@s.write(message)

				if not @s.wait(2)
					return false if (try+=1) > 2
					redo
				end

				sleep 0.1
				ans = @s.gets("\r")
				if not ans
					return false if (try+=1) > 2
					redo
				end
				redo if not ans
				puts ans if @v
			end			
			return ans
		end
	end
end

