command commandList[] = {
  {"dinput", 1, digit_input_loop, input_setup},
  {"mem", 0, memory, noconf},
  {"blinker", 1, blinker, output_setup}
};

const int nbCmd = sizeof(commandList) / sizeof(command);            // Number of functions implemented

// Fonctions supportees :

// Useful for task that don't need configuration
void noconf(int* args, int* space) {
}

// Put the pin args[0] in input mode
void input_setup(int* args, int* space) {
  pinMode(args[0], INPUT);
  space[0] = 2;
}

// Put the pin args[0] in output mode
void output_setup(int* args, int* space) {
  pinMode(args[0], OUTPUT);
  space[0] = 0;
}

// Read digital input on pin args[0]
void digit_input_loop(int num, int* args, int* space) {
  space[1] = digitalRead(args[0]);
  if (space[1] != space[0]) {
    snd_message(num, space[1]);
    space[0] = space[1];
  }
}

// Transmit free memory
void memory(int num, int* args, int* space) {
  snd_message(num, availableMemory());
}


// Blink the pin args[0]
void blinker(int num, int* args, int* space) {
  if (space[0] == 0){
    digitalWrite(args[0], HIGH);
    space[0] = 1;
  }
  else {
    digitalWrite(args[0], LOW);
    space[0] = 0;
  }
}

