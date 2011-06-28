// {"command", nb of arguments, core function, configuration function}
command commandList[] = {
  {"din", 0, digit_input_loop,  input_setup},
  {"bli", 0, blinker,           output_setup},
  {"ain", 0, analog_input_loop, input_setup},
  {"1wi", 0, one_wire_loop,     one_wire_setup}
};

const byte nbCmd = sizeof(commandList) / sizeof(command);            // Number of functions implemented

// Fonctions supportees :

// Useful for task that don't need configuration
void noconf(int pin, int* args, int* space) {
}

void one_wire_setup(int pin, int* args, int* space){
  OneWire one = OneWire(pin);
//  new OneWire(uint8_t(pin));
//  space[0] = (int)one;
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

// Read digital input on pin
void digit_input_loop(int pin, int* args, int* space) {
  space[1] = digitalRead(pin);
  if (space[1] != space[0]) {
    snd_message(pin, space[1]);
    space[0] = space[1];
  }
}

// Read analog input on pin
void analog_input_loop(int pin, int* args, int* space){
  snd_message(pin, analogRead(pin));
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

