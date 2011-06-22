const int valsize = 15;
const int nbsize = 5;

int id = 0;
char idstr[valsize];
char msgrcv[nbsize][valsize];
byte read = 0;
int i = 0;
int j = 0;

void setup(){
  //id = EEPROM.read(0);  
  id = 25;
  itoa(id, idstr, 10);
  
  // Identification :
  Serial.begin(9600);
  do {
    i = 0;
    j = 0;
    while(not(Serial.available())) {
      delay(100);
    }
    do{
      msgrcv[j][i++] = Serial.read();
      if (msgrcv[j][i-1] == ' ') {
        msgrcv[j][i-1] = '\0';
        i = 0;
        j++;
      }
    } while (Serial.available() && (i < valsize-1) && (j < nbsize-1));
    msgrcv[j][i++] = '\0';
  } while (strcmp(idstr, msgrcv[0]) != 0);
}

void loop() {
  for (i = 0; i <= j; i++){
    Serial.print(msgrcv[i]);
    Serial.print(' ');
  }
  delay(1000);
  Serial.println();
}

