#include <OneWire.h>
#include <avr/eeprom.h>

const int signature = 12345;             // Should change at each firmware modification
const int atomicMsgSize = 202;           // TODO verifier
const int wordSize = 15;                 // Max size of an argument
const int maxArgsCmd = 2;                // Max arguments of unique command
const int spaceSize = 2;                 // Size of personnal space of the tasks
const int wordNb = 10;                   // Max number of words in the message (including id and mode...)
const int msgSize = (wordSize+1)*wordNb; // Max size of a message transmitted
const int baudrate = 19200;              // Serial baudrate
const int nbPin = 21;                    // Nb of pin (and max nb of task)

typedef void (*looper)(int, int*, int*); // Arguments are : pin, list of arguments, personnal space
typedef void (*setuper)(int, int*, int*);
typedef struct {
  char name[4];        // Command to call such a task
  int nbArgs;          // Number of arguments the task require
  looper function;     // Function that will be called
  setuper configure;   // Function that will be called one time
} command;

typedef struct {
  looper function;        // Function associated with the task
  int args[maxArgsCmd];   // Arguments the server gave
  unsigned int period;    // Period of repetition of the task
  unsigned long lastTime; // Last time the task has been called
  int space[spaceSize];   // Personnal space of the task
  byte idx_command;       // Index of the command in commandList
  byte pin;               // First pin used, and index in taskList
} task;

task* taskList[nbPin];

byte nbTask = 0;

char idstr[wordSize];

