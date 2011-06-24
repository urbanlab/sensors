void setup(){
  Serial.begin(baudrate);
  Serial.flush();
  set_id(EEPROM.read(0));
  snd_message("NEW");
  process_message(true);
  //while(get_id() == 0) {
  //  process_message(true);
  //}
}

void loop() {
  process_message(false);
  for (int i=0 ; i < nbTask ; i++) {
    if (cycleCheck(taskList[i].lastTime, taskList[i].period))
      taskList[i].function(i, taskList[i].args, taskList[i].space);
  }
}

int availableMemory()
{
 int size = 8192;
 byte *buf;
 while ((buf = (byte *) malloc(--size)) == NULL);
 free(buf);
 return size;
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

void add_task(void (*function)(int, int*, int*), int period) {
  taskList[nbTask].function = function;
  taskList[nbTask].period = period;
  taskList[nbTask].lastTime = 0;
  
  nbTask++;
}

void snd_message(char* message) {
  char buff[atomicMsgSize];
  strcpy(buff, idstr);
  strcat(buff, " ");
  strcat(buff, message);
  Serial.println(buff);
}

void snd_message(unsigned int sensor, int value) {
  char message[msgSize];
  char valueBuff[wordSize];
  itoa(value, valueBuff, 10);
  itoa(sensor, message, 10);
  strcat(message, " ");
  strcat(message, valueBuff);
  snd_message(message);
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

    if (strcmp(msgrcv[0], idstr) == 0) { // identified
      valid = true;
      boolean accepted = false;
      char resp[msgSize];
      switch (msgrcv[1][0]) {
        
      case 'l':
        accepted = true;
        strcpy(resp, "");
        for (int i=0 ; i < nbCmd ; i++){
          strcat(resp, commandList[i].name);
          strcat(resp, " ");
        }
        break;
        
      case 's':
        accepted = true;
        set_id(atoi(msgrcv[2]));
        strcpy(resp, "NEW");
        break;
        
      case 'a':
        for (int i=0 ; i < nbCmd ; i++){
          if((strcmp(commandList[i].name, msgrcv[2]) == 0) && (commandList[i].nbArgs == nbArgs - 4)){
            accepted = true;
            add_task(commandList[i].function, atoi(msgrcv[3]));
            for (int j = 0 ; j < nbArgs-4 ; j++)
              taskList[nbTask-1].args[j] = atoi(msgrcv[j+4]);   // Assignation des arguments
            commandList[i].configure(taskList[nbTask-1].args, taskList[nbTask-1].space);
            strcpy(resp, "OK ");
            strcat(resp, itoa(nbTask-1, "", 10));
          }
        }
        break;
      }
      if (!accepted) strcpy(resp, "KO");
      snd_message(resp);
    }
  } while (!valid && block);
  return valid;
}

// Get a word from serial line.
// Return true if something was available
// arg block define if the function shourd wait for a word
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

