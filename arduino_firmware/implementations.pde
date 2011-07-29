// {"command", nb of arguments, core function, configuration function}
command commandList[] = {
  {"din", 0, digit_input_loop,  input_setup,    noconf        },
  {"bli", 0, blinker,           output_setup,   output_cleaner},
  {"ain", 0, analog_input_loop, input_setup,    noconf        },
  {"1wi", 0, one_wire_loop,     one_wire_setup, noconf        },
  {"mem", 0, snd_memory_loop,   noconf,         noconf        },
  {"i2c", 2, i2c_loop,          i2c_setup,      noconf        },
  {"pls", 1, pulse_input_loop,  input_setup,    noconf        }
};

const byte nbCmd = sizeof(commandList) / sizeof(command);            // Number of functions implemented

// Fonctions supportees :

// args[0] : 0 for LOW, 1 for HIGH
void pulse_input_loop(int pin, int* args, int* space) {
  snd_message(pin, pulseIn(pin, args[0], 50000)); //will not block more than 50ms
}

// Useful for task that don't need configuration
void noconf(int pin, int* args, int* space) {
}

// args[0] : address (33 pour la boussole)
// args[1] : get data command (65)
void i2c_setup(int pin, int* args, int* space) {
  Wire.begin();
  Wire.beginTransmission(args[0]);
  Wire.send(args[1]);
  Wire.endTransmission();
}

void i2c_loop(int pin, int* args, int* space) {
  Wire.requestFrom(args[0], 2);
  snd_message(pin, (Wire.receive() << 8) + Wire.receive());
  Wire.beginTransmission(args[0]);
  Wire.send(args[1]);
  Wire.endTransmission();
}

void one_wire_setup(int pin, int* args, int* space){
  OneWire one = OneWire(pin);
  one.reset();
  one.skip();
  one.write(0x44);
}

void one_wire_loop(int pin, int* args, int* space){
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
void input_setup(int pin, int* args, int* space) {
  pinMode(pin, INPUT);
  space[0] = 2;
}

// Put the pin in output mode
void output_setup(int pin, int* args, int* space) {
  pinMode(pin, OUTPUT);
  space[0] = 0;
}

// Put the pin at low state
void output_cleaner(int pin, int* args, int* space) {
  digitalWrite(pin, LOW);
}

// Read digital input on pin
void digit_input_loop(int pin, int* args, int* space) {
  int val = digitalRead(pin);
  if (val != space[0]) {
    snd_message(pin, val);
    space[0] = val;
  }
}

// Read analog input on pin
void analog_input_loop(int pin, int* args, int* space){
  snd_message(pin, analogRead(pin));
}

void snd_memory_loop(int pin, int* args, int* space){
  snd_message(pin, availableMemory());
}

// Blink the pin
void blinker(int pin, int* args, int* space) {
  if (space[0] == 0){
    digitalWrite(pin, HIGH);
    space[0] = 1;
  }
  else {
    digitalWrite(pin, LOW);
    space[0] = 0;
  }
}

