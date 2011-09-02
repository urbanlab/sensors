#include <OneWire.h>
#include <avr/eeprom.h>
#include <Wire.h>
//#define SERIAL_DEBUG
#define CONF_XBEE

const int signature = 12351;             // Should change at each firmware modification
const int spaceSize = 2;                 // Size of personnal space of the tasks
const int wordNb = 10;                   // Max number of words in the message (including id and mode...)
const int msgSize = 50;                  // Max size of a message transmitted
const int baudrate = 9600;              // Serial baudrate
const int nbPin = 22;                    // Nb of pin (and max nb of task)

typedef void (*looper)(int, int*); // Arguments are : pin, personnal space (containing optionals arguments)
typedef void (*setuper)(int, int*);
typedef void (*destroyer)(int, int*);
typedef struct {
  char name[4];        // Command to call the task
  int nbArgs;          // Number of arguments the task require
  looper function;     // Function that will be called to send the infos
  setuper configure;   // Function that will be called first
  destroyer clean;     // Function that will be called when deleting the task
} command;

typedef struct {
  looper function;        // Function associated with the task
  unsigned int period;    // Period of repetition of the task
  unsigned long lastTime; // Last time the task has been called
  int space[spaceSize];   // Personnal space of the task
  byte idx_command;       // Index of the command in commandList
  byte pin;               // First pin used, and index in taskList
} task;

task* taskList[nbPin];

byte nbTask = 0;

char idstr[4];
char completeMessageSnd[msgSize]; // buffer that will be sent
char* messageSnd; // buffer where function will write to send messages
char buffRcv[msgSize] = "\0";
unsigned long lastMsgTime = 0;
unsigned int lastMsgPos = 0;

