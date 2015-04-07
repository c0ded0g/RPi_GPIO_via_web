# 
# This is fully-annotated code for a server running on my RPi which allows
# a client to read/write to the GPIOs etc.
#
# documentation etc:
# http://www.sinatrarb.com
# http://sinatra-org-book.herokuapp.com/
# https://www.ruby-lang.org/en/documentation/
# 
# v0.01   01 April 2015
# v0.02   02 April       fixed problem with switch for displaying LEDs in client
#                        added missing code to display analog input value
# v0.03   07 April       played around with <div> formatting, resaved

require 'sinatra'		# required for web server
require 'sinatra-websocket'	# required for sockets
require 'pi_piper'		# required for GPIO access
require 'rubygems'		# required for ??


# ADC
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
  result = 0
  (0..11).each do
    clockpin.on
    clockpin.off
    result <<= 1
    adc_out.read
    if adc_out.on?
      result |= 0x1
    end
  end
  cspin.on
  result >> 1
end

clock   = PiPiper::Pin.new :pin => 18, :direction => :out
adc_out = PiPiper::Pin.new :pin => 23
adc_in  = PiPiper::Pin.new :pin => 24, :direction => :out
cs      = PiPiper::Pin.new :pin => 25, :direction => :out
adc_pin = 0



# set up the LED pins as outputs
pinRedLed   = PiPiper::Pin.new :pin => 17, :direction => :out
pinGreenLed = PiPiper::Pin.new :pin => 27, :direction => :out
pinBlueLed  = PiPiper::Pin.new :pin => 22, :direction => :out

# constants, Ruby syntax rule is that constants start with upper case
# LED status possibilities (on/off):
LEDon  = true
LEDoff = false
# index values into an array containing status info of each LED
IdxRedLed   = 0
IdxGreenLed = 1
IdxBlueLed  = 2

# an array containing the status of each LED
ledStatus = [LEDoff, LEDoff, LEDoff]

# Messages. Use constants to avoid possible typos.
# How to ensure client conforms?
# client --> server
M_redLedClicked   = 'redLed clicked'
M_greenLedClicked = 'greenLed clicked'
M_blueLedClicked  = 'blueLed clicked'
# server --> client
M_redOff   = 'redLed off'
M_redOn    = 'redLed on'
M_greenOff = 'greenLed off'
M_greenOn  = 'greenLed on'
M_blueOff  = 'blueLed off'
M_blueOn   = 'blueLed on'

# read analog pin & update the clients
Thread.new do
  # execute this in a new thread so that the pins are read
  # and/or writted in parallel with the server code
  loop do
    sleep(1)
    # temporary code to flash the red LED while testing
    if (pinRedLed.read == 0)
      pinRedLed.on
      ledStatus[IdxRedLed] == LEDon
      EM.next_tick { settings.sockets.each{|s| s.send(M_redOn) } }
    else
      pinRedLed.off
      ledStatus[IdxRedLed] == LEDoff
      EM.next_tick { settings.sockets.each{|s| s.send(M_redOff) } }
    end
    # get ADC value and send with prefix
    value = read_adc(adc_pin, clock, adc_in, adc_out, cs)
    EM.next_tick { settings.sockets.each{|s| s.send("ADC1 #{value}") } }
  end
end


set :server, 'thin'		# sets the handle used for built-n webserver
set :sockets, []		# creates an empty list, called sockets
set :port, 2001			# server port, default is 4567
set :bind, '0.0.0.0'		# server IP address


# ROUTES

get '/' do
  # the incoming request object can be accessed through the request method
  # e.g. request.port, request.path_info etc
  # here we first see if the request is a websocket request ...
  if !request.websocket?
    # not a websocket, serve up the index html page
    # NOTE: the page is defined in-line below rather than in /views/index.erb
    erb :index
  else
    # websocket logic:
    request.websocket do |ws|
      # code block, uses local variable ws
      ws.onopen do |handshake|
        # websocket connection's readyState has changed to 'OPEN'
        ws.send("Hello "+request.ip)
        settings.sockets << ws
        # double less than <<
        # adds this websocket to the sockets list variable that was created earlier

        # send messages to the client to set the LED colours when connection opens        
        if (pinRedLed.read == 0)
          ledStatus[IdxRedLed] == LEDoff
          EM.next_tick { settings.sockets.each{|s| s.send(M_redOff) } }
        else 
          ledStatus[IdxRedLed] == LEDon
          EM.next_tick { settings.sockets.each{|s| s.send(M_redOn) } }
        end
        
        if (pinGreenLed.read == 0)
          ledStatus[IdxGreenLed] == LEDoff
	  EM.next_tick { settings.sockets.each{|s| s.send(M_greenOff) } }
        else 
          ledStatus[IdxGreenLed] == LEDon
          EM.next_tick { settings.sockets.each{|s| s.send(M_greenOn) } }
        end
        
        if (pinBlueLed.read == 0)
          ledStatus[IdxBlueLed] == LEDoff
          EM.next_tick { settings.sockets.each{|s| s.send(M_blueOff) } }
        else 
          ledStatus[IdxBlueLed] == LEDon
          EM.next_tick { settings.sockets.each{|s| s.send(M_blueOn) } }
        end
        
      end
      
      ws.onmessage do |msg|
        # called when message is received
        #
        # EM is event manager ... this schedules a procedure for execution 
        # immediately after the next 'turn' through the reactor core.
        # For each websocket in sockets, invoke the websocket's send method
        # with argument 'msg'. This transmits data (text string) to the
        # server
        #
        case msg

	  # RED LED      
          when M_redLedClicked
            if (pinRedLed.read == 0)
            #if (ledStatus[RedLed] == LEDoff)
              ledStatus[IdxRedLed] = LEDon;
              EM.next_tick { settings.sockets.each{|s| s.send(M_redOn) } };
              pinRedLed.on
              #`sudo python scripts/redledon.py`;
            else
              ledStatus[IdxRedLed] = LEDoff;
              EM.next_tick { settings.sockets.each{|s| s.send(M_redOff) } };
              pinRedLed.off
              #`sudo python scripts/redledoff.py`;
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
            #if (ledStatus[GreenLed] == LEDoff)
              ledStatus[IdxGreenLed] = LEDon;
              EM.next_tick { settings.sockets.each{|s| s.send(M_greenOn) } };
              pinGreenLed.on
              #`sudo python scripts/greenledon.py`;
            else
              ledStatus[IdxGreenLed] = LEDoff;
              EM.next_tick { settings.sockets.each{|s| s.send(M_greenOff) } };
              pinGreenLed.off
              #`sudo python scripts/greenledoff.py`;
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
            #if (ledStatus[BlueLed] == LEDoff)
              ledStatus[IdxBlueLed] = LEDon;
              EM.next_tick { settings.sockets.each{|s| s.send(M_blueOn) } };
              pinBlueLed.on
              #`sudo python scripts/blueledon.py`;
            else
              ledStatus[IdxBlueLed] = LEDoff;
              EM.next_tick { settings.sockets.each{|s| s.send(M_blueOff) } };
              pinBlueLed.off
              #`sudo python scripts/blueledoff.py`;
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
        # websocket connection's readyState changes to 'CLOSED'
        warn("websocket closed")
        settings.sockets.delete(ws)
      end
    end
  end
end

        

__END__

@@ index
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
"http://www.w3.org/TR/html4/loose.dtd">
<html>

  <meta charset="UTF-8">
  <title>LED CONTROL PANEL</title>
  <body>
  
    <div id="container" style="width:600px; height:500px">
    
       <div id="header" style="background-color:#FFA500;">
            <text style="margin-bottom:0;text-align:center;">Control Panel</text>
            <table width="100%">
            <!-- th = table header cell, td = table data cell -->
            <tr>
                <th align="left">RPi 2</th>
                <th align="right">Address:Port</th>
            </tr>
            <tr>
                <td align="left"><label id="msg1"></label>you are :</td>
                <td align="right"><label id="ipaddr"></label></td>
            </tr>
            </table>
       </div>
       
       <!-- ------------------------ -->
       <form id="form" style="background-color:#FFA500;border:solid 2px black">
         <input type="text" id="input" value="type a command" size="50" maxlength="20"></input>
       </form>
       <!-- ------------------------ -->

       <div id="LEDs" style="background-color:#EEEEEE;height:100px;width:186px;border:solid 2px black;position: absolute; top: 110px; left: 10px; ">
           <svg xmlns="http://www.w3.org/2000/svg">
           <circle id="redLed"   cx="30"  cy="25" r="10" fill="gray" stroke="black" stroke-width="4"/>
           <circle id="greenLed" cx="60"  cy="25" r="10" fill="gray" stroke="black" stroke-width="4"/>
           <circle id="blueLed"  cx="90"  cy="25" r="10" fill="gray" stroke="black" stroke-width="4"/>
           </svg>
       </div>

       
       <div id="msgs" style="background-color:#99FF99;height:296px;width:200px;overflow:scroll;border:solid 2px black;position: absolute; top: 110px; left: 200px; ">
       </div>
       
       <div id="status" style="background-color:#FFD700;width:186px;height:300px;border:solid 2px black;position: absolute; top: 210px; left: 10px; ">
            <b>analog inputs:</b><br>
            <FONT FACE="courier">
            AN1: <label id="an1"></label> <br> <meter id="meter1" x="27" y="20" value="512" min="0" max="1024" low="100" high="900"></meter> <br>
            AN2: <label id="an2"></label> <br> <meter id="meter2" x="27" y="20" value="100" min="0" max="1024" low="100" high="900"></meter> <br>
            AN3: <label id="an3"></label> <br> <meter id="meter3" x="27" y="20" value="200" min="0" max="1024" low="100" high="900"></meter> <br>
            AN4: <label id="an4"></label> <br> <meter id="meter4" x="27" y="20" value="300" min="0" max="1024" low="100" high="900"></meter> <br>
            AN5: <label id="an5"></label> <br> <meter id="meter5" x="27" y="20" value="400" min="0" max="1024" low="100" high="900"></meter> <br>
            </FONT>
            </p>
       </div>
       
       <div id="buttons" style="background-color:#99FF99;height:100px;width:200px;border:solid 2px black;position: absolute; top: 410px; left: 200px; ">
           <input type="button" name="toggleMsgs" id="toggleMsgs" value="MSG on/off" fill="red" style="position: absolute;left:10px; top:10px">
       </div>

    </div>  
  </body>
  
  <script type="text/javascript">
  
    // javascript self-executing functions:
    //
    // (function (){...code}());
    // is equivalent (I think) to 
    // ...code
    // and (function (){...code}(x));
    // is equivalent to passing x to the function
    // 
    // benefit: variables declared in the self-executing code
    // are available only within the self-executing code

    var displayMessages = true;
    
    // add leading zeros to pad out a number 
    function pad(num, size) {
      var s = num+"";
      while (s.length < size) s = "0" + s;
      return s;
    }
    
    window.onload = function(){
      (function(){

        //---------------------------------------------------
        // assign a variable to an unnamed function
        // calling the variable effectively calls the function
        
        var show = function(el){
          
          return function(msg){ el.innerHTML = msg + '<br />' + el.innerHTML; }
        }(document.getElementById('msgs'));
        
        // document.getElementById('msgs') is passed to the function as parameter 'el'
        // the function returns another function (unnamed), to which the parameter msg is passed
        // and the result is that the innerHTML of element msgs has the text 'msg' added to the
        // front of it

        // update GPIO (read/write etc) based on param1 & param2, the first two words in the received message
        var update_GPIO = function(param1,param2){
              switch (param1){
                  case 'redLed':
                    // fall through
                  case 'greenLed':
                    // fall through
                  case 'blueLed':
                    update_LEDs(param1, param2)
                    break;
                  case 'ADC1':
                    update_Meters(param2)
                    break;
                  case 'Hello':
                    update_Greeting(param2)
                    break;
                  default:
              }
        }
        var update_LEDs = function(a,b,c) {
          return function(indic,msg){
              if (indic == 'redLed') {
                if (msg == 'on')  {a.style.fill='red'}
                if (msg == 'off') {a.style.fill='brown'}
              }
              if (indic == 'greenLed') {
                if (msg == 'on')  {b.style.fill='lightgreen'}
                if (msg == 'off') {b.style.fill='darkgreen'}
              }
              if (indic == 'blueLed') {
                if (msg == 'on')  {c.style.fill='dodgerblue'}
                if (msg == 'off') {c.style.fill='darkblue'}
              }
          }
        }(document.getElementById('redLed'),document.getElementById('greenLed'),document.getElementById('blueLed'));
        
        var update_Meters = function(a,b) {
          return function(x){
              a.innerHTML = x
              b.value=parseInt(x)
              }
        } (document.getElementById('an1'),document.getElementById('meter1'))
        
        var update_Greeting = function(a) {
          return function(x){
              a.innerHTML = x
              }
        } (document.getElementById('ipaddr'))
        
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
          var param1 = received_msg[0]
          if (received_msg.length > 1) {
            var param2 = received_msg[1]
          } else {
            var param2 = "-"
          }
            
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
          if (displayMessages) {
            show(timeStamp+m.data)
          }
          
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
          
        // when an LED object is clicked, send a message to the server 
        
	// RED        
        var senderRed = function(i1){
          i1.onclick = function(){
            ws.send('redLed clicked')
          }
        }(document.getElementById('redLed'));
        // GREEN
        var senderGreen = function(i1){
          i1.onclick = function(){
            ws.send('greenLed clicked')
          }
        }(document.getElementById('greenLed'));
        // BLUE
        var senderBlue = function(i1){
          i1.onclick = function(){
            ws.send('blueLed clicked')
          }
        }(document.getElementById('blueLed'));



        var toggleMessages = function(i1){
          i1.onclick = function(){
            displayMessages = !displayMessages;
            if (displayMessages) {
              i1.fill = "green"
            } else {
              i1.fill = "red"
            }
          }
        }(document.getElementById('toggleMsgs'));
        
      })();
      
    }
  </script>
</html>