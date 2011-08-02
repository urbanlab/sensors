#include <OneWire.h>
#include <avr/eeprom.h>
#include <Wire.h>
//#define SERIAL_DEBUG

const int signature = 12350;             // Should change at each firmware modification
const int atomicMsgSize = 50;           // TODO verifier
const int wordSize = 15;                 // Max size of an argument
//const int maxArgsCmd = 2;                // Max arguments of unique command
const int spaceSize = 2;                 // Size of personnal space of the tasks
const int wordNb = 10;                   // Max number of words in the message (including id and mode...)
const int msgSize = 45;//(wordSize+1)*wordNb; // Max size of a message transmitted
const int baudrate = 19200;              // Serial baudrate
const int nbPin = 21;                    // Nb of pin (and max nb of task)

typedef void (*looper)(int, int*); // Arguments are : pin, personnal space (containing optionals arguments)
typedef void (*setuper)(int, int*);
typedef void (*destroyer)(int, int*);
typedef struct {
  char name[4];        // Command to call such a task
  int nbArgs;          // Number of arguments the task require
  looper function;     // Function that will be called to send the infos
  setuper configure;   // Function that will be called first
  destroyer clean;     // Function that will be called when deleting the task
} command;

typedef struct {
  looper function;        // Function associated with the task
//  int args[maxArgsCmd];   // Arguments the server gave
  unsigned int period;    // Period of repetition of the task
  unsigned long lastTime; // Last time the task has been called
  int space[spaceSize];   // Personnal space of the task
  byte idx_command;       // Index of the command in commandList
  byte pin;               // First pin used, and index in taskList
} task;

task* taskList[nbPin];

byte nbTask = 0;

char idstr[wordSize];

