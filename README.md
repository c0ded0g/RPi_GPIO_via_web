# RPi_GPIO_via_web
read and write RPi GPIO via web interface

Uses Ruby, Sinatra, pi_piper to allow a client to read/write GPIO on RPi.

Configuration:
* an RBG LED connected to the RPi via 330-ohm resistors to GPIOs 17, 27, 22
* an ADC chip (MCP3008) connected to GPIOs 18 (clk), 23 (Dout), 24 (Din), 25 (CS)
* a potentiometer connected between 0 & 3v3 with wiper connected to ADC channel 0

