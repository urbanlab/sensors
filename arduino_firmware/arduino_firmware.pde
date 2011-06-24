#include <EEPROM.h>

const int atomicMsgSize = 202;            //TODO verifier
const int wordSize = 15;                 // Max size of an argument
const int maxArgs = 7;                   // Max number of arguments
const int maxArgsCmd = 3;
const int wordNb = maxArgs+3;            // Max number of words in the message (including id and mode...)
const int msgSize = (wordSize+1)*wordNb; // Max size of a message transmitted
const int maxTask = 5;                   // Max number of tasks executed
const int baudrate = 19200;              // Serial baudrate


typedef void (*looper)(int, int*, int*); // Arguments are : id of the task, list of arguments, personnal space
typedef void (*setuper)(int*, int*);
typedef struct {
  char* name;          // Command to call such a task
  int nbArgs;          // Number of arguments the task require
  looper function;     // Function that will be called
  setuper configure;   // Function that will be called one time
} command;

typedef struct {
  looper function;        // Function associated with the task
  int args[maxArgsCmd];      // Arguments the server gave
  int period;             // Period of repetition of the task
  unsigned long lastTime; // Last time the task has been called
  int space[2];           // Personnal space of the task
} task;

task taskList[maxTask];
unsigned int nbTask = 0;

char idstr[wordSize];

