#include <EEPROM.h>

typedef struct {
  char* name;
  int nbArgs;
  void (*function)(int*);
  void (*configuration)(int*);
} command;

typedef struct {
  void (*function)(int*);
  int args[10];
  int period;
  unsigned long lastTime;
  //int space[10]; // espace de variable propre. utile ?
} task;

command commandList[] = {
  {"transm", 1, transm, noconf},
  {"blinker", 2, blinker, noconf}
};

task taskList[10];
const int wordSize = 15;  // Max size of arguments transmitted
const int wordNb = 5;     // Max number of arguments
const int msgSize = 200;
const int maxTask = 5;
const int nbCmd = 2;            // Number of functions implemented
//const char* CMDS[] =   {"transm", "blink"}; // Command names
//const int  NBARGS[] =  { 1      , 2}; // Number of arguments for each command
//void (*FUNC[])(int*) = { transm , blinker}; // Function to call for each command

char idstr[wordSize];

byte read = 0;

//unsigned int period[maxTask];
//unsigned int tasks[maxTask];
///unsigned long lastTime[maxTask];
//unsigned int args_start_at[maxTask];

unsigned int nbTask = 0;

int ARGS[50];

void setup(){
  Serial.begin(9600);
  Serial.flush();
  set_id(EEPROM.read(0));
  snd_message("NEW");
  
  while(get_id() == 0) {
    process_message(true);
  }
}

void loop() {
  process_message(false);
  for (int i=0 ; i < nbTask ; i++) {
    if (cycleCheck(taskList[i].lastTime, taskList[i].period))
      taskList[i].function(taskList[i].args);//FUNC[tasks[i]](ARGS + args_start_at[i]);
  }
}

boolean cycleCheck(unsigned long &lastTime, int period)
{
  unsigned long currentTime = millis();
  if(currentTime - lastTime >= period)
  {
    lastTime = currentTime;
    return true;
  }
  else
    return false;
}

void add_task(void (*function)(int*), int period) {
  taskList[nbTask].function = function;
  //taskList[nbTask].args = args;
  taskList[nbTask].period = period;
  taskList[nbTask].lastTime = 0;
  
  nbTask++;
}

void snd_message(char* message) {
  char buff[202]; // Taille maximum atomique
  strcpy(buff, idstr);
  strcat(buff, " ");
  strcat(buff, message);
  Serial.println(buff);
}

// Get and process a message from the server.
// Return true if a message for the arduino arrived
boolean process_message(boolean block){
  boolean valid = false;
  char msgrcv[wordNb][wordSize];
  char wrd[wordSize] = "";
  int nbArgs;
  do {
    nbArgs = 0;
    do {
      get_word(wrd, block);
      strcpy(msgrcv[nbArgs++], wrd);
    } while (Serial.available());

    if (strcmp(msgrcv[0], idstr) == 0) {
      valid = true;
      boolean accepted = false;
      char resp[msgSize] = "";
      switch (msgrcv[1][0]) {
      case 'l':
        for (int i=0 ; i < nbCmd ; i++){
          strcat(resp, commandList[i].name);
          strcat(resp, " ");
        }
        snd_message(resp);
        break;
      case 's':
        set_id(atoi(msgrcv[2]));
        snd_message("NEW");
        break;
      case 'a':
        for (int i=0 ; i < nbCmd ; i++){
          if((strcmp(commandList[i].name, msgrcv[2]) == 0) && (commandList[i].nbArgs == nbArgs - 4)){
            accepted = true;
            add_task(commandList[i].function, atoi(msgrcv[3]));
            for (int j = 0 ; j < nbArgs-4 ; j++)
              taskList[nbTask-1].args[j] = atoi(msgrcv[j+4]);   // Assignation des arguments
          }
          if (!accepted) snd_message("KO");
        }
        break;
      default:
        snd_message("KO");
      }
      
    }
  } while (!valid && block);
  return valid;
}

boolean get_word(char* wrd, boolean block){
  int i=0;
  boolean valid = false;
  do {
    if(Serial.available()){
       delay(10);
       while( Serial.available() && i< wordSize-1 && wrd[i] != ' ' ) {
          wrd[i++] = Serial.read();
          if (wrd[i-1] == ' ')
            i--;
       }
       wrd[i]='\0';
       valid = true;
    }
  } while (!valid && block);
  return valid;
}

void set_id(byte id){
  EEPROM.write(0, id);
  itoa(id, idstr, 10);
}

boolean get_id(){
  return EEPROM.read(0);
}

// Fonctions supportees :
void noconf(int* args) {
}

void transm(int* ARGS) {
  Serial.println(ARGS[0]);
}

void blinker(int* ARGS) {
  if (ARGS[1] == 0){
    digitalWrite(ARGS[0], HIGH);
    ARGS[1] = 1;
  }
  else {
    digitalWrite(ARGS[0], LOW);
    ARGS[1] = 0;
  }
}
