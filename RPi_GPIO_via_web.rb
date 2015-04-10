################################################################################# 
# 										#
# FILE:		RPi_GPIO_via_web.rb						#
# 										#
# USAGE:	sudo ruby RPi_GPIO_via_web.rb					#
# 										#
# DESCRIPTION:	Access and control RPi GPIO via the web.			#
#		My first attempt at this (Ruby, Sinatra), so lots of comments!	#
# 										#
# OPTIONS: 	---								#
# REQUIREMENTS: ---								#
# BUGS: 	---								#
# NOTES: 	---								#
# 										#
# AUTHOR: 	Mark Wrigley							#
# COMPANY: 	---								#
# VERSION: 	0.05								#
# CREATED: 	01.04.2015							#
# REVISION: 	10.04.2015							#
# 										#
################################################################################# 

################################################################################# 
# CONFIGURATION									#
# 										#
# 	tri-colour LED connected to GPIO 17, 27, 22				#
# 	MCP3008 (ADC) connected to GPIO 18, 23 24, 25				#
# 										#
################################################################################# 

################################################################################# 
# NOTES:									#
# 	http://www.sinatrarb.com						#
# 	http://sinatra-org-book.herokuapp.com/					#
# 	https://www.ruby-lang.org/en/documentation/				#
# 										#
#################################################################################

require 'sinatra'		# required for web server
require 'sinatra-websocket'	# required for sockets
require 'pi_piper'		# required for GPIO access
require 'rubygems'		# required for ??

#===============================================================================#
# ADC										#
#===============================================================================#
def read_adc(adc_pin, clockpin, adc_in, adc_out, cspin)
  cspin.on
  clockpin.off
  cspin.off
  command_out = adc_pin
  command_out |= 0x18
  command_out <<= 3
  (0..4).each do
    adc_in.update_value((command_out & 0x80) > 0)	
    command_out <<= 1					
    clockpin.on						
    clockpin.off					
  end
  clockpin.on		
  clockpin.off	
  result = 0		
  (0..9).each do	
    clockpin.on		
    clockpin.off	
    result <<= 1	
    adc_out.read	
    if adc_out.on?	
      result |= 0x1	
    end
  end
  cspin.on		
  return result
end

#===============================================================================#
# GPIO PIN CONFIGURATION							#
#===============================================================================#

# SPI - serial peripheral interface to MCP3008:
clock   = PiPiper::Pin.new :pin => 18, :direction => :out
adc_out = PiPiper::Pin.new :pin => 23
adc_in  = PiPiper::Pin.new :pin => 24, :direction => :out
cs      = PiPiper::Pin.new :pin => 25, :direction => :out

# tricolour LED:
pinRedLed   = PiPiper::Pin.new :pin => 17, :direction => :out
pinGreenLed = PiPiper::Pin.new :pin => 27, :direction => :out
pinBlueLed  = PiPiper::Pin.new :pin => 22, :direction => :out

#===============================================================================#
# CONSTANTS									#
#===============================================================================#
# NOTE: all constants in Ruby start with upper case character

# LED status possibilities (on/off):
LEDon  = true
LEDoff = false

# index values into an array containing status info of each LED
IdxRedLed   = 0
IdxGreenLed = 1
IdxBlueLed  = 2

# Messages: client --> server
M_redLedClicked   = 'redled clicked'
M_greenLedClicked = 'greenled clicked'
M_blueLedClicked  = 'blueled clicked'

# Messages: server --> client
M_redOff   = 'redled off'
M_redOn    = 'redled on'
M_greenOff = 'greenled off'
M_greenOn  = 'greenled on'
M_blueOff  = 'blueled off'
M_blueOn   = 'blueled on'

#===============================================================================#
# VARIABLES									#
#===============================================================================#

# an array containing the status of each LED
ledStatus = [LEDoff, LEDoff, LEDoff]
flashRate = 1.0
updateRate = 5.0

#===============================================================================#
# THINGS TO DO INDEPENDENTLY OF THE SERVER					#
#===============================================================================#

# read analog pins & send updates to the clients
Thread.new do
  loop do
    sleep(updateRate)
    (0..7).each do |channel| 
      value = read_adc(channel, clock, adc_in, adc_out, cs)
      EM.next_tick { settings.sockets.each{|s| s.send("adc"+channel.to_s+" #{value}") } }
    end
  end
end

# temporary code to flash the red LED while testing
Thread.new do
  loop do
    sleep(flashRate)
    if (pinRedLed.read == 0)
      pinRedLed.on
      ledStatus[IdxRedLed] == LEDon
      EM.next_tick { settings.sockets.each{|s| s.send(M_redOn) } }
    else
      pinRedLed.off
      ledStatus[IdxRedLed] == LEDoff
      EM.next_tick { settings.sockets.each{|s| s.send(M_redOff) } }
    end
  end
end

#===============================================================================#
# SETTINGS									#
#===============================================================================#

set :server, 'thin'		# sets the handle used for built-in webserver
set :sockets, []		# creates an empty list, called sockets
set :port, 2001			# server port, default is 4567, I use 2001 to suit my router port mapping
set :bind, '0.0.0.0'		# server IP address

#===============================================================================#
# ROUTES									#
#===============================================================================#

get '/' do
  if !request.websocket?
    # not a websocket request, serve up the home html page
    # NOTE: the page is defined in-line below rather than in /views/index.erb
    erb :index
  else
    # websocket logic:
    request.websocket do |ws|
    
      ws.onopen do |handshake|
        # send information only to the client that just connected:
        ws.send("Hello "+request.ip)		
        if (pinRedLed.read == 0);   ws.send(M_redOff)   else ws.send(M_redOn)   end
        if (pinGreenLed.read == 0); ws.send(M_greenOff) else ws.send(M_greenOn) end
        if (pinBlueLed.read == 0);  ws.send(M_blueOff)  else ws.send(M_blueOn)  end
        # then add this to the list of sockets
        settings.sockets << ws			
      end
      
      ws.onmessage do |msg|
        case msg.downcase
          # TO DO: put in limits to these rates
          when 'flash rate up'
            flashRate /= 2.0
          when 'flash rate down'
            flashRate += 1
          when 'refresh rate up'
            updateRate /= 2.0
          when 'refresh rate down'
            updateRate += 1
	  # RED LED      
          when M_redLedClicked
            if (pinRedLed.read == 0)
              ledStatus[IdxRedLed] = LEDon;
              EM.next_tick { settings.sockets.each{|s| s.send(M_redOn) } };
              pinRedLed.on
            else
              ledStatus[IdxRedLed] = LEDoff;
              EM.next_tick { settings.sockets.each{|s| s.send(M_redOff) } };
              pinRedLed.off
            end
          when M_redOff
            ledStatus[IdxRedLed] = LEDoff;
            EM.next_tick { settings.sockets.each{|s| s.send(M_redOff) } };
            pinRedLed.off
          when M_redOn
            ledStatus[IdxRedLed] = LEDon;
            EM.next_tick { settings.sockets.each{|s| s.send(M_redOn) } };
            pinRedLed.on
          # GREEN LED    
          when M_greenLedClicked
            if (pinGreenLed.read == 0)
              ledStatus[IdxGreenLed] = LEDon;
              EM.next_tick { settings.sockets.each{|s| s.send(M_greenOn) } };
              pinGreenLed.on
            else
              ledStatus[IdxGreenLed] = LEDoff;
              EM.next_tick { settings.sockets.each{|s| s.send(M_greenOff) } };
              pinGreenLed.off
            end
          when M_greenOff
            ledStatus[IdxGreenLed] = LEDoff;
            EM.next_tick { settings.sockets.each{|s| s.send(M_greenOff) } };
            pinGreenLed.off
          when M_greenOn
            ledStatus[IdxGreenLed] = LEDon;
            EM.next_tick { settings.sockets.each{|s| s.send(M_greenOn) } };
            pinGreenLed.on
	  # BLUE LED
          when M_blueLedClicked
            if (pinBlueLed.read == 0)
              ledStatus[IdxBlueLed] = LEDon;
              EM.next_tick { settings.sockets.each{|s| s.send(M_blueOn) } };
              pinBlueLed.on
            else
              ledStatus[IdxBlueLed] = LEDoff;
              EM.next_tick { settings.sockets.each{|s| s.send(M_blueOff) } };
              pinBlueLed.off
            end
          when M_blueOff
            ledStatus[IdxBlueLed] = LEDoff;
            EM.next_tick { settings.sockets.each{|s| s.send(M_blueOff) } };
            pinBlueLed.off
          when M_blueOn
            ledStatus[IdxBlueLed] = LEDon;
            EM.next_tick { settings.sockets.each{|s| s.send(M_blueOn) } };
            pinBlueLed.on
	  # OTHERWISE, send the message back to the clients
          else
            EM.next_tick { settings.sockets.each{|s| s.send(msg) } }
        end
      end

      ws.onclose do
        warn("websocket closed")
        settings.sockets.delete(ws)
      end
      
    end
  end
end

get '/params' do
  erb :params
end
        

__END__

@@ index
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
"http://www.w3.org/TR/html4/loose.dtd">
<html>

	<meta charset="UTF-8">
	<title>RPi2</title>
	<body>
  
		<div id="container" style="width:600px; height:500px">
		  <FONT FACE="verdana" size="2">
		<!-- ------------------------ -->
			<div id="header" style="background-color:#FFA500;">
				<text style="margin-bottom:0;text-align:center;">Control Panel</text>
				<table width="100%">
					<!-- th = table header cell, td = table data cell -->
					<tr>
						<th align="left">RPi 2</th>
						<th align="right">IP address</th>
					</tr>
					<tr>
						<td align="left"><label id="msg1"></label>you are :</td>
						<td align="right"><label id="ipaddr"></label></td>
					</tr>
				</table>
			</div>
			<!-- ------------------------ -->
			<form id="form" style="background-color:#FFA500;border:solid 2px black">
				<input type="text" id="input" value="type a command" size="50" maxlength="20" style="background-color:#FFB500"></input>
			</form>
			<!-- ------------------------ -->
			<div id="LEDs" style="background-color:#EEEEEE;height:100px;width:186px;border:solid 2px black;position: absolute; top: 110px; left: 10px; ">
				<svg xmlns="http://www.w3.org/2000/svg">
				<circle id="redLed"   cx="30"  cy="25" r="10" fill="gray" stroke="black" stroke-width="4"/>
				<circle id="greenLed" cx="60"  cy="25" r="10" fill="gray" stroke="black" stroke-width="4"/>
				<circle id="blueLed"  cx="90"  cy="25" r="10" fill="gray" stroke="black" stroke-width="4"/>
				</svg>
			</div>
			<!-- ------------------------ -->
			<div id="msgs" style="background-color:#99FF99;height:346px;width:200px;overflow:scroll;border:solid 2px black;position: absolute; top: 110px; left: 200px; ">
			</div>
			<!-- ------------------------ -->
			<div id="status" style="background-color:#FFD700;width:186px;height:350px;border:solid 2px black;position: absolute; top: 210px; left: 10px; ">
				<b>analog inputs:</b><br>
				<FONT FACE="courier">
				AN0: <label id="an0"></label> <br> <meter id="meter0" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				AN1: <label id="an1"></label> <br> <meter id="meter1" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				AN2: <label id="an2"></label> <br> <meter id="meter2" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				AN3: <label id="an3"></label> <br> <meter id="meter3" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				AN4: <label id="an4"></label> <br> <meter id="meter4" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				AN5: <label id="an5"></label> <br> <meter id="meter5" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				AN6: <label id="an6"></label> <br> <meter id="meter6" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				AN7: <label id="an7"></label> <br> <meter id="meter7" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
				</FONT>
				</p>
			</div>
			<!-- ------------------------ -->
			<div id="buttons" style="background-color:#99FF99;height:100px;width:200px;border:solid 2px black;position: absolute; top: 460px; left: 200px; ">
				
				<input type="button" name="toggleMsgs" id="toggleMsgs" value="turn messages on/off" fill="red" style="position: absolute;left:10px; top:25px">
				<input type="button" name="clearMsgs" id="clearMsgs" value="clear messages" fill="red" style="position: absolute;left:10px; top:50px">
				
			</div>
			<div id="links" style="background-color:lightblue;height:146px;width:200px;overflow:scroll;border:solid 2px black;position: absolute; top: 110px; left: 402px; ">
				<p>Click <a href="/params"> here for the params</a></p>
			</div>
			<!-- ------------------------ -->
		</div>  
	</body>
  
	<script type="text/javascript">
	
  		var displayMessages = true;
   
		function pad(num, size) {
			// add leading zeros to pad out a number 
			var s = num+"";
			while (s.length < size) s = "0" + s;
			return s;
		}

		function updateMeter(meter,value){
			// adjust analog meter    
			var s1 = meter.slice(-1)
			document.getElementById('an'+s1).innerHTML = value
			document.getElementById('meter'+s1).value = parseInt(value)
		}


		window.onload = function(){
			(function(){
		
	        		var show = function(el){
					return function(msg){ el.innerHTML = msg + '<br />' + el.innerHTML; }
				}(document.getElementById('msgs'));
        
				var update_GPIO = function(param1,param2){
					switch (param1){
						case 'redled':
						case 'greenled':
						case 'blueled':
							update_LEDs(param1, param2)
							break;
						case 'adc0':
						case 'adc1':
						case 'adc2':
						case 'adc3':
						case 'adc4':
						case 'adc5':
						case 'adc6':
						case 'adc7':
							updateMeter(param1,param2)
							break;
						case 'hello':
							update_Greeting(param2)
							break;
						case 'message','msg':
							update_Message(param2)
							break;
						default:
					}
				}
        
				var update_LEDs = function(a,b,c) {
					return function(indic,msg){
						if (indic == 'redled') {
							if (msg == 'on')  {a.style.fill='red'}
							if (msg == 'off') {a.style.fill='brown'}
						}
						if (indic == 'greenled') {
							if (msg == 'on')  {b.style.fill='lightgreen'}
							if (msg == 'off') {b.style.fill='darkgreen'}
						}
						if (indic == 'blueled') {
							if (msg == 'on')  {c.style.fill='dodgerblue'}
							if (msg == 'off') {c.style.fill='darkblue'}
						}
					}
				}(document.getElementById('redLed'),document.getElementById('greenLed'),document.getElementById('blueLed'));
        
				var update_Greeting = function(a) {
					return function(x){a.innerHTML = x}
				} (document.getElementById('ipaddr'))

				var update_Message = function(a) {
					return function(x){
						if (x == "on")    {displayMessages = true}
						if (x == "off")   {displayMessages = false}
						if (x == "clear") {a.innerHTML = ""}
					}
				} (document.getElementById('msgs'))

        
				// ws is my websocket connection in the client
				var ws = new WebSocket('ws://' + window.location.host + window.location.pathname);

				ws.onopen    = function()  { show('websocket opened'); };
				// this calls function show, which returns an unnamed function that
				// takes 'websocket opened' as a parameter (called msg), and adds it
				// to the front of the HTML text in the document element referred to
				// by the ID 'msgs'
                
				ws.onclose   = function()  { show('websocket closed'); };
        
				ws.onmessage = function(m) { 
					// break the message into parts based on space separator
					// the first two words are important
					var received_msg = m.data.split(' ');
					var param1 = received_msg[0].toLowerCase()
					param2 = (received_msg.length > 1) ? received_msg[1].toLowerCase() : "-";
					// this is a short way to write the following if else statement
					// if (received_msg.length > 1) {
					// 	var param2 = received_msg[1].toLowerCase()
					// } else {
					// 	var param2 = "-"
					// }
            
					// build a timestamp
					var d = new Date();
					var hr = d.getHours();
					var mn = d.getMinutes();
					var sc = d.getSeconds();
					hr = pad(hr,2)
					mn = pad(mn,2)
					sc = pad(sc,2)
					var timeStamp = '['+hr+':'+mn+':'+sc+'] '
          
					// act on the GPIO pins as necessary
					update_GPIO(param1,param2)

					//show(timeStamp+param1+'/'+param2)
					if (displayMessages) {show(timeStamp+m.data)}
          
				};

				// when something is typed in the input box (form), send
				// it to the server
				var sender = function(f){
					var input     = document.getElementById('input');
					input.onclick = function(){ input.value = ">>" };
					input.onfocus = function(){ input.value = ">" };
					f.onsubmit    = function(){
						ws.send(input.value);
						input.value = "send a message";
						return false;
					}
				}(document.getElementById('form'));
          
				// when an LED object is clicked or button pressed, send a message to the server 
			
				// RED
				var senderRed = function(i1){
					i1.onclick = function(){ws.send('redLed clicked')}
				}(document.getElementById('redLed'));
				
				// GREEN
				var senderGreen = function(i1){
					i1.onclick = function(){ws.send('greenLed clicked')}
				}(document.getElementById('greenLed'));
				
				// BLUE
				var senderBlue = function(i1){
					i1.onclick = function(){ws.send('blueLed clicked')}
				}(document.getElementById('blueLed'));

				// MESSAGES ON/OFF
				var toggleMessages = function(i1){
					i1.onclick = function(){displayMessages = !displayMessages}
				}(document.getElementById('toggleMsgs'));

				// CLEAR MESSAGES
        			var clearMessages = function(i1){
					i1.onclick = function(){update_Message('clear')}
				}(document.getElementById('clearMsgs'));
        
			})();
		}
	</script>
</html>

@@ params
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
"http://www.w3.org/TR/html4/loose.dtd">
<html>
	<meta charset="UTF-8">
	<title>RPi2 params</title>
	<body>
	current parameter settings are:
	<p>Click <a href="/">here</a> to go home</p>
	</body>
</html>