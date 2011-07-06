void setup(){
  Serial.begin(baudrate);
  Serial.flush();
  //Serial.println(availableMemory());
  restore_state();
  snd_message("NEW");
  while(get_id() == 0) {
    process_message(true);
  }
}

void loop() {
  process_message(false);
  for (int i=0 ; i < nbPin ; i++) {
    if ((taskList[i] != NULL) && cycleCheck(taskList[i]->lastTime, taskList[i]->period))
      taskList[i]->function(i, taskList[i]->args, taskList[i]->space);
  }
}
/*
void* operator new(size_t size) {return malloc(size); }

void operator delete(void* ptr) { free(ptr); }*/

boolean cycleCheck(unsigned long &lastTime, unsigned int period)
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

// this function will return the number of bytes currently free in RAM
// written by David A. Mellis
// based on code by Rob Faludi http://www.faludi.com

int availableMemory() {
  int size = 1024; // Use 2048 with ATmega328
  byte *buf;

  while ((buf = (byte *) malloc(--size)) == NULL)
    ;

  free(buf);

  return size;
}

boolean add_task(unsigned int pin, byte idx_command, unsigned int period, int* args) {
  if (taskList[pin])
    delete_task(pin);
  taskList[pin] = (task*) malloc(sizeof(task));
  if (taskList[pin] == NULL) {
    return false;
  }
  else {
    taskList[pin]->function = commandList[idx_command].function;
    taskList[pin]->period = period;
    taskList[pin]->lastTime = millis();
    for (int i = 0; i<commandList[idx_command].nbArgs; i++)
      taskList[pin]->args[i] = args[i];
    taskList[pin]->idx_command = idx_command;
    commandList[idx_command].configure(pin, taskList[pin]->args, taskList[pin]->space);
    
    nbTask++;
    return true;
  }
}

void delete_task(unsigned int pin) {
  if (taskList[pin]) {
    free(taskList[pin]);
    taskList[pin] = NULL;
    nbTask--;
  }
}

void snd_message(char* message) {
  char buff[atomicMsgSize];
  strcpy(buff, idstr);
  strcat(buff, " ");
  strcat(buff, message);
  Serial.println(buff);
}

void snd_message(unsigned int sensor, int value) {
  char buff[atomicMsgSize];
  char message[msgSize];
  char valueBuff[wordSize];
  itoa(value, valueBuff, 10);
  itoa(sensor, message, 10);
  strcat(message, " ");
  strcat(message, valueBuff);
  strcpy(buff, idstr);
  strcat(buff, " SENS ");
  strcat(buff, message);
  Serial.println(buff);
}

// Get and process a message from the server.
// Return true if a message for the arduino arrived
boolean process_message(boolean block){
  boolean valid = false;
  do {
    char car = ' ';
    int nbArgs = 1;
    char* msgrcv[wordNb];
    char msg[msgSize] = "";
    boolean rcvd = false;
    do {                                  // Reception message
      rcvd = get_message(msg, block);
    } while (!rcvd && block);
    
    msgrcv[0] = msg;
    int i=0;
    while (car != '\0') {                 // Decoupage message
      car = msg[i];
      if (car == ' '){
        msg[i] = '\0';
        msgrcv[nbArgs++] = msg+i+1;
      }
      i++;
    }    

    if (strcmp(msgrcv[0], idstr) == 0) {  // Identification
      valid = true;
      boolean accepted = false;
      char resp[msgSize];
      switch (msgrcv[1][0]) {             // Traitement
        
      /*case 'p':
        accepted = true;
        print_eeprom();
      break;*/
      case 'p':
        accepted = true;
        strcpy(resp, "PONG");
      break;
      
      case 's':
        accepted = true;
        strcpy(resp, "SAVED");
        save_state();
      break;
      
      /*case 'r':
        accepted = true;
        strcpy(resp, "OK");
        restore_state();
      break;*/
        
      case 'l':
        accepted = true;
        strcpy(resp, "LIST ");
        for (byte j = 0 ; j < nbCmd ; j++){
          strcat(resp, commandList[j].name);
          strcat(resp, " ");
        }
        break;
        
      case 't':
        accepted = true;
        strcpy(resp, "TASKS ");
        for (int i = 0 ; i < nbPin ; i++){
          if (taskList[i] != NULL) {
            char pin[3] = "";
            itoa(i, pin, 10);
            strcat(resp, pin);
            strcat(resp, ":");
            strcat(resp, commandList[taskList[i]->idx_command].name);
            strcat(resp, " ");
          }
        }
        break;
        
      case 'i':
        accepted = true;
        set_id(atoi(msgrcv[2]));
        strcpy(resp, "NEW");
        break;
        
      case 'a':
        for (int i = 0 ; i < nbCmd ; i++){
          if((strcmp(commandList[i].name, msgrcv[2]) == 0) && (commandList[i].nbArgs == nbArgs - 5) && atoi(msgrcv[4]) < nbPin){ // Meme nom et meme nombre d'arg
            unsigned int period = atoi(msgrcv[3]);
            unsigned int pin = atoi(msgrcv[4]);
            int args[maxArgsCmd];
            for (int j = 0 ; j < commandList[i].nbArgs ; j++) {
              args[j] = atoi(msgrcv[j+5]);
            }
            accepted = add_task(pin, i, period, args);
            if (accepted) {
              strcpy(resp, "ADD ");
              strcat(resp, msgrcv[4]);
            }
          }
        }
        break;
        
      case 'd':
        accepted = true;
        strcpy(resp, "DEL");
        delete_task(atoi(msgrcv[2]));
        break;
      }
      if (!accepted) strcpy(resp, "KO");
      snd_message(resp);
    }
  } while (!valid && block);
  return valid;
}

boolean get_message(char* msg, boolean block){
  int i=0;
  boolean valid = false;
  do{
    if(Serial.available()){
       delay(100);
       while( Serial.available() && i< msgSize-1) {
          msg[i++] = Serial.read();
       }
       msg[i++]='\0';
       valid = true;
    }
  } while(!valid && block);
  return valid;
}

// Get a word from serial line.
// Return true if something was available
// arg block define if the function shourd wait for a word
/*
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
}*/

byte read_byte(int address) {
  return eeprom_read_byte((unsigned char *) address);
}

void write_byte(unsigned int address, byte value) {
  eeprom_write_byte((unsigned char *) address, value);
}

unsigned int read_int(unsigned int address) {
  return eeprom_read_word((unsigned int *) address);
}

void write_int(int address, unsigned int value) {
  eeprom_write_word((unsigned int *) address, value);
}

void set_id(byte id){
  write_byte(2, id);
  itoa(id, idstr, 10);
}

byte get_id(){
  return read_byte(2);
}

unsigned int save_task(unsigned int idx_task, unsigned int address) {
  task* t = taskList[idx_task];
  write_int(address, idx_task);
  address+=2;
  write_byte(address, t->idx_command);
  address+=1;
  write_int(address, t->period);
  address+=2;
  for (int i = 0; i < commandList[t->idx_command].nbArgs; i++){
    write_int(address, t->args[i]);
    address+=2;
  }
  return address;
}

unsigned int restore_task(unsigned int address) {
  int pin = read_int(address);
  address += 2;
  int idx_command = read_byte(address);
  address += 1;
  int period = read_int(address);
  address += 2;
  int args[maxArgsCmd];
  for (int i=0; i<commandList[idx_command].nbArgs; i++){
    taskList[pin]->args[i] = read_int(address);
    address += 2;
  }
  add_task(pin, idx_command, period, args);
  return address;
}

void save_state(){
  write_int(0, signature);
  write_byte(3, nbTask);
  int address = 4;
  for (byte i=0; i < nbPin; i++){
    if (taskList[i])
      address = save_task(i, address);
  }
}

void restore_state(){
  if (read_int(0) == signature) {
    set_id(get_id());
    byte nb = read_byte(3);
    unsigned int address = 4;
    for (byte i=0; i<nb; i++)
      address = restore_task(address);
  }
  else {
    set_id(0);
    save_state();
  }
}
/*
void print_eeprom(){
  int i = 0;
  while(i<512){
    Serial.print(i);
    Serial.print("\t");
    Serial.print((int)read_byte(i));
    Serial.print("\t");
    Serial.print(read_int(i));
    Serial.println();
    i++;
  }
}
*/
