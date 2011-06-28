// {"command", nb of arguments, core function, configuration function}
command commandList[] = {
  {"din", 0, digit_input_loop, input_setup},
  {"bli", 0, blinker, output_setup},
  {"ain", 0, analog_input_loop, input_setup}
};

const byte nbCmd = sizeof(commandList) / sizeof(command);            // Number of functions implemented

// Fonctions supportees :

// Useful for task that don't need configuration
void noconf(int pin, int* args, int* space) {
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

