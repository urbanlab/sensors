// {"command", nb of arguments, core function, configuration function}
command commandList[] = {
  // Digital input : read a binary value and send it when it has changed
  {"din", 0, digit_input_loop,  input_setup,    noconf        },
  // Digital output : switch to 1 an output at creation and 0 at destruction
  // looping it make it blink
  {"dou", 0, blinker,           output_setup,   output_cleaner},
  // Analog input : read regulary an analog voltage (1 unit = 0.00322V on FIO /!\)
  {"ain", 0, analog_input_loop, input_setup,    noconf        },
  // 1wi : read in 1wi a value from a dallas temperature sensor (TODO generalize)
  {"1wi", 0, one_wire_loop,     one_wire_setup, noconf        },
  // i2c : read in 2wire a value. first args is the request message, 2nd is the reading address
  {"i2c", 2, i2c_loop,          i2c_setup,      noconf        },
  // pulse : read a value with pulse style. return the nomber of micro-s between 2 fronts
  // see http://www.arduino.cc/en/Reference/PulseIn for arg1
  {"pls", 1, pulse_input_loop,  input_setup,    noconf        }
};

const byte nbCmd = sizeof(commandList) / sizeof(command);            // Number of functions implemented

// Fonctions supportees :

// args[0] : 0 for LOW, 1 for HIGH
//
void pulse_input_loop(int pin, int* space) {
  snd_message(pin, pulseIn(pin, space[0], (unsigned long) 50000)); //will not block more than 50ms
}

// Useful for task that don't need conf, loop or destroyer
//
void noconf(int pin, int* space) {
}

// space[0] : address (33 pour la boussole)
// space[1] : get data command (65)
//
void i2c_setup(int pin, int* space) {
  Wire.begin();
  Wire.beginTransmission(space[0]);
  Wire.send(space[1]);
  Wire.endTransmission();
}

void i2c_loop(int pin, int* space) {
  Wire.requestFrom(space[0], 2);
  snd_message(pin, (Wire.receive() << 8) + Wire.receive());
  Wire.beginTransmission(space[0]);
  Wire.send(space[1]);
  Wire.endTransmission();
}

void one_wire_setup(int pin, int* space){
  OneWire one = OneWire(pin);
  one.reset();
  one.skip();
  one.write(0x44);
}

void one_wire_loop(int pin, int* space){
  int data0;
  int data1;
  OneWire one = OneWire(pin);
  one.reset();
  one.skip();
  one.write(0xBE);
  data0 = one.read();
  data1 = one.read();
  int temp = (data1<<8) + data0;
  if (bitRead(data1, 0) == 1)
    temp = -1*((temp^0xffff) + 1);
  snd_message(pin, temp);
  one.reset();
  one.skip();
  one.write(0x44);
}

// Put the pin in input mode
void input_setup(int pin, int* space) {
  pinMode(pin, INPUT);
  space[0] = 2;
}

// Put the pin in output mode and switch it to 1
void output_setup(int pin, int* space) {
  pinMode(pin, OUTPUT);
  digitalWrite(pin, HIGH);
  space[0] = 1;
}

// Put the pin at low state
void output_cleaner(int pin, int* space) {
  digitalWrite(pin, LOW);
}

// Read digital input on pin
void digit_input_loop(int pin, int* space) {
  int val = digitalRead(pin);
  if (val != space[0]) {
    snd_message(pin, val);
    space[0] = val;
  }
}

// Read analog input on pin
void analog_input_loop(int pin, int* space){
  snd_message(pin, analogRead(pin));
}

// Blink the pin
void blinker(int pin, int* space) {
  if (space[0] == 0){
    digitalWrite(pin, HIGH);
    space[0] = 1;
  }
  else {
    digitalWrite(pin, LOW);
    space[0] = 0;
  }
}

