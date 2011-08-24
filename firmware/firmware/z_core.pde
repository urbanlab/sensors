void setup(){
  Serial.begin(baudrate);
  Serial.flush();
  delay(1000);
  restore_state();
  strcpy(messageSnd, "NEW");
  snd_complete();
  while(get_id() == 0) {
    read_input(true);
  }
}

void loop() {
  read_input(false);
  for (int i=0 ; i < nbPin ; i++) {
    if ((taskList[i] != NULL) && (taskList[i]->period != 0) && cycleCheck(taskList[i]->lastTime, taskList[i]->period))
      taskList[i]->function(i, taskList[i]->space);
  }
}

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
      taskList[pin]->space[i] = args[i];
    taskList[pin]->idx_command = idx_command;
    commandList[idx_command].configure(pin, taskList[pin]->space);

    nbTask++;
    return true;
  }
}

boolean delete_task(unsigned int pin) {
  if (taskList[pin]) {
    commandList[taskList[pin]->idx_command].clean(pin, taskList[pin]->space);
    free(taskList[pin]);
    taskList[pin] = NULL;
    nbTask--;
    return true;
  }
  return false;
}

void snd_complete() {
  strcat(completeMessageSnd, "\n"); // println(s) = print(s); println(). not atomic.
  Serial.print(completeMessageSnd); 
}

void snd_message(unsigned int sensor, int value) {
  strcpy(messageSnd, "SENS ");
  char* intStr = messageSnd + strlen(messageSnd);
  itoa(sensor, intStr, 10);
  strcat(messageSnd, " ");
  intStr = messageSnd + strlen(messageSnd);
  itoa(value, intStr, 10);
  snd_complete();
}

// Get and process a message from the server.
// Return true if a message for the arduino arrived
//
boolean read_input(boolean block){
  boolean valid = false;
  do {
    boolean rcvd = false;
    do {                                  // Reception message
      rcvd = append_message();
    } while (!rcvd && block);
    if (rcvd) {
      valid = process_message();
    }
  } while (!valid && block);
}

boolean process_message(){
  char car = ' ';
  int nbArgs = 1;
  int i=0;
  char* msgrcv[wordNb];
  boolean identified = false;
  msgrcv[0] = buffRcv;
  while (car != '\0') {                 // Decoupage message
    car = buffRcv[i];
    if (car == ' '){
      buffRcv[i] = '\0';
      msgrcv[nbArgs++] = buffRcv+i+1;
    }
    i++;
  }
  if (strcmp(msgrcv[0], idstr) == 0) {  // Identification
    identified = true;
    boolean accepted = false;
    switch (msgrcv[1][0]) {             // Traitement
    case 'p':
      strcpy(messageSnd, "PONG");
      break;

    case 's':
      save_state();
      strcpy(messageSnd, "SAVED");
      break;

    case 'l':
      strcpy(messageSnd, "LIST ");
      for (byte j = 0 ; j < nbCmd ; j++){
        strcat(messageSnd, commandList[j].name);
        strcat(messageSnd, " ");
      }
      break;

    case 't':
      strcpy(messageSnd, "TASKS ");
      for (int i = 0 ; i < nbPin ; i++){
        if (taskList[i] != NULL) {
          char pin[3] = "";
          itoa(i, pin, 10);
          strcat(messageSnd, pin);
          strcat(messageSnd, ":");
          strcat(messageSnd, commandList[taskList[i]->idx_command].name);
          strcat(messageSnd, " ");
        }
      }
      break;

    case 'i':
      set_id(atoi(msgrcv[2]));
      strcpy(messageSnd, "ID");
      break;

    case 'r':
      for (unsigned int i = 0 ; i < nbPin ; i++)
        delete_task(i);
      strcpy(messageSnd, "RST");
      break;

    case 'a':
      for (int i = 0 ; i < nbCmd ; i++){
        if((strcmp(commandList[i].name, msgrcv[2]) == 0) && (commandList[i].nbArgs == nbArgs - 5) && atoi(msgrcv[4]) < nbPin){ // Meme nom et meme nombre d'arg
          unsigned int period = atoi(msgrcv[3]);
          unsigned int pin = atoi(msgrcv[4]);
          int args[spaceSize];
          for (int j = 0 ; j < commandList[i].nbArgs ; j++) {
            args[j] = atoi(msgrcv[j+5]);
          }
          accepted = add_task(pin, i, period, args);
        }
      }
      strcpy(messageSnd, "ADD ");
      strcat(messageSnd, msgrcv[4]);
      strcat(messageSnd, accepted ? " OK" : " KO");
      break;

    case 'd':
      strcpy(messageSnd, "DEL ");
      strcat(messageSnd, msgrcv[2]);
      strcat(messageSnd, delete_task(atoi(msgrcv[2])) ? " OK" : " KO");
      break;
    }
    snd_complete();
  }
  lastMsgPos = 0;
  return identified;
}

#ifndef SERIAL_DEBUG
boolean append_message(){
  boolean valid = false;
  if ((millis() - lastMsgTime) > 100) { // Last message was not complete or invalid, delete it.
    lastMsgPos = 0;
  }
  while(Serial.available() && lastMsgPos < msgSize-1){
    delay(10);
    lastMsgTime = millis();
    buffRcv[lastMsgPos++] = Serial.read();
  }
  if (buffRcv[lastMsgPos-1] == '\n'){
    valid = true;
    buffRcv[lastMsgPos-1] = '\0';
  }
  return valid;
}

#else /* SERIAL_DEBUG */
// For science, you monster.
boolean append_message(){
  boolean valid = false;
  while(Serial.available() && lastMsgPos < msgSize-1){
    delay(10);
    valid = true;
    buffRcv[lastMsgPos++] = Serial.read();
  }
  if (valid){
    buffRcv[lastMsgPos++] = '\0';
  }
  return valid;
}
#endif /* SERIAL_DEBUG */

byte read_byte(unsigned int address) {
  return eeprom_read_byte((unsigned char *) address);
}

void write_byte(unsigned int address, byte value) {
  eeprom_write_byte((unsigned char *) address, value);
}

unsigned int read_int(unsigned int address) {
  return eeprom_read_word((unsigned int *) address);
}

void write_int(unsigned int address, unsigned int value) {
  eeprom_write_word((unsigned int *) address, value);
}

void set_id(byte id){
  write_byte(2, id);
  itoa(id, idstr, 10);
  itoa(id, completeMessageSnd, 10);
  strcat(completeMessageSnd, " ");
  messageSnd = completeMessageSnd + strlen(completeMessageSnd); // position messageSnd in order to have the id as a prefix of it.
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
  for (int i = 0; i < spaceSize; i++){
    write_int(address, t->space[i]);
    address+=2;
  }
  return address;
}

void save_state(){
  write_int(0, signature);
}

void restore_state(){
  if (read_int(0) == signature) {
    set_id(get_id());
    byte nb = read_byte(3);
  }
  else {
    set_id(0);
    save_state();
  }
}

