/*
 *  SecuritySystem_keypad.pde - Arduino Security System I/O Board
 *
 *  Copyright (c) 2012 Jon Brule <brulejr@gmail.com>
 *  All rights reserved.
 *
 *
 *  LICENSE
 *  -------
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *  
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *  
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 *
 *  EXPLANATION
 *  -----------
 *  This sketch provides the core logic for the I/O (sensor and output)
 *  portion of the Arduino Security System.
 *
 * PCF8574 Notes:
 *   - With A0, A1 and A2 of PCF8574 to ground I2C address is 0x20
 *   - With A0, A1 and A2 of PCF8574A to ground I2C address is 0x38
 */

// configurable options (uncomment to enable)
//#define RESET_CLOCK
//#define RESET_PARMS
//#define DEBUG

// library includes
#include <BufferedShiftReg_I2C.h>
#include <EEPROM.h>
#include <I2CDecodedKeyPad.h>
#include <LiquidCrystal_I2C.h>
#include <RTClib.h>
#include <TimerOne.h> 
#include <Wire.h>

#define VERSION "v0.1.7"

#define SENSOR_SHORT 0
#define SENSOR_NORMAL 1
#define SENSOR_TRIPPED 2
#define SENSOR_OPEN 3

#define STATE_UNARMED 0
#define STATE_ARMING 1
#define STATE_ARMED 2
#define STATE_TRIPPED 3
#define STATE_ALERTING 4
#define STATE_FAULT 5

#define DPIN_MUX_S0 8
#define DPIN_MUX_S1 9
#define DPIN_MUX_S2 10

#define DPIN_SIREN 11
#define DPIN_MAINT_MODE 12

#define APIN_MUX_OUT 0

#define MP_SENSOR_A 0
#define MP_SENSOR_B 1

#define ARMING_TIMEOUT 5
#define ALERT_TIMEOUT 5

#define SR_I2C_ADDR 0x39
#define SR_LED_A 0
#define SR_LED_B 1
#define SR_SIREN 7

#define KEYPAD_I2C_ADDR 0x38
#define KEYPAD_LED_ARMED 6
#define KEYPAD_LED_FAULT 5
#define KEYPAD_TIMEOUT 15
#define MAX_KEY_LENGTH 4

#define LCD_I2C_ADDR 0x3A

#define SETTINGS_I2C_ADDR 0x3B
#define SETTINGS_DIP_MAINT_ENABLE 0
#define SETTINGS_DIP_SILENT_ENABLE 1

#define MAX_MAINT_MODES 4
#define MAX_LENGTH_MODE 7
#define DEFAULT_MAINT_MODE 0
#define MAINT_MODE_ARMING_TIMEOUT 1
#define MAINT_MODE_ALERT_TIMEOUT 2
#define MAINT_MODE_KEYPAD_TIMEOUT 3
#define EEPROM_ARMING_TIMEOUT 0
#define EEPROM_ALERT_TIMEOUT 1
#define EEPROM_KEYPAD_TIMEOUT 2
char modes[MAX_MAINT_MODES][MAX_LENGTH_MODE] = {
  { '\0' }, 
  { 'A','R','M','_','T','O','\0' }, 
  { 'A','L','R','_','T','O','\0' }, 
  { 'K','E','Y','_','T','O','\0' }
};


// system switches variables
BufferedShiftReg_I2C switches(SETTINGS_I2C_ADDR);

// sensor state variables
BufferedShiftReg_I2C sensorStatus(SR_I2C_ADDR, B00000000);

// real-time clock handling variables
RTC_DS1307 RTC;

// keypad handling variables
I2CDecodedKeypad kpd(KEYPAD_I2C_ADDR, B00011111);
char allowedPasskey[MAX_KEY_LENGTH+1] = { '1','2','3','4','\0' };
long keyMillis = 0;
bool keyAvailable = false;
char keypad[MAX_KEY_LENGTH+1] = { '\0' };
int keypadPos = 0;
int keypadTimeout;

// lcd handling variables
LiquidCrystal_I2C lcd(LCD_I2C_ADDR, 20, 4);  // set the LCD for a 20 chars and 4 line display

// system state variables
int alertTimeout;
long alertMillis = 0;
int armingTimeout;
bool fault;
bool maintEnabled;
int maintMode = 0;
long maintModeMillis = 0;
bool silentMode;
bool systemLED = false;
long systemMillis = 0;
byte systemState = STATE_UNARMED;

// misc variables
char buffer[20];

//------------------------------------------------------------------------------
/* Initialize the Security System firmware.
 */
void setup() {
  Serial.begin(57600);

  // initialize digital pins
  pinMode(DPIN_MUX_S0, OUTPUT);
  pinMode(DPIN_MUX_S1, OUTPUT);
  pinMode(DPIN_MUX_S2, OUTPUT);

  pinMode(DPIN_SIREN, OUTPUT);
  
  pinMode(DPIN_MAINT_MODE, INPUT);

  // initialize timer1 interrupt
  Timer1.initialize(250000);
  Timer1.attachInterrupt(timerOneCallback);

  // initialize clock device
  Wire.begin();
  RTC.begin();
  #ifdef RESET_CLOCK
    if (! RTC.isrunning()) {
      Serial.println("RTC is NOT running!");
      RTC.adjust(DateTime(__DATE__, __TIME__));
    }
  #endif
  
  // initialize switches for reading
  switches.setBuffer();
  switches.writeBuffer();

  // initialize keypad device
  kpd.init();
  kpd.clearBuffer();
  kpd.writeBuffer();

  // clear the shift register
  sensorStatus.clearBuffer();
  kpd.writeBuffer();
  
  // initialize settings
  #ifdef RESET_PARMS
    EEPROM.write(EEPROM_ARMING_TIMEOUT, ARMING_TIMEOUT);
    EEPROM.write(EEPROM_ALERT_TIMEOUT, ALERT_TIMEOUT);
    EEPROM.write(EEPROM_KEYPAD_TIMEOUT, KEYPAD_TIMEOUT);
  #endif
  armingTimeout = getSetting(EEPROM_ARMING_TIMEOUT, ARMING_TIMEOUT);
  alertTimeout = getSetting(EEPROM_ALERT_TIMEOUT, ALERT_TIMEOUT);
  keypadTimeout = getSetting(EEPROM_KEYPAD_TIMEOUT, KEYPAD_TIMEOUT);
  
  // initialize lcd device
  lcd.init();
  lcd.backlight();
  lcd.clear();
  
  // display splash screen for five seconds
  lcd.setCursor(0, 0);  
  lcd.print("Home Security System");
  lcd.setCursor(7, 2); 
  lcd.print(VERSION);
  lcd.setCursor(4, 3); 
  lcd.print("by Jon Brule");
  delay(3000);
  lcd.clear();
}

//------------------------------------------------------------------------------
/* Main Loop: Monitor the Security System sensors.
 */
void loop() {
  checkSwitches();
  checkKeypad();
  fault = false;
  checkSensor(MP_SENSOR_A, SR_LED_A);
  checkSensor(MP_SENSOR_B, SR_LED_B);
  sensorStatus.writeBuffer();
  fault |= (systemState == STATE_FAULT);
  kpd.write(KEYPAD_LED_FAULT, fault);
  kpd.writeBuffer();
  updateLCD();
}

//------------------------------------------------------------------------------
/* Handle monitoring analysis logic
 */
void timerOneCallback(void) {    // timer compare interrupt service routine
  checkSystemState();
  if (!maintEnabled) {
    digitalWrite(DPIN_SIREN, (!silentMode) && (systemState >= STATE_ALERTING));
  }
}

//------------------------------------------------------------------------------
/* Checks the keypad for a new digit
 */
void checkKeypad() {
  char k = kpd.getKeyStroke();
  if (k > 0) {
    keyMillis = millis();
    if (k == '*') {
      keypad[keypadPos = 0] = '\0';
      keyAvailable = false;
    } 
    else if (k == '#') {
      keyAvailable = true;
    } 
    else {
      if (keypadPos >= MAX_KEY_LENGTH) {
        for (int i = 0; i < MAX_KEY_LENGTH; i++) {
          keypad[i] = keypad[i + 1];
        }
        keypad[MAX_KEY_LENGTH] = '\0';
        keypadPos = MAX_KEY_LENGTH - 1;
      }
      keypad[keypadPos++] = k;
      keypad[keypadPos] = '\0';
      #ifdef DEBUG
        Serial.print("(rawkey: ");
        Serial.print(kpd.getRawKey());
        Serial.print(", keyval: ");
        Serial.print(k, BYTE);
        Serial.print(", keypad: ");
        Serial.print(keypad);
        Serial.println(")");
      #endif
    }
  }
}

//------------------------------------------------------------------------------
/* Checks the state of the given sensor
 */
byte checkSensor(byte sensorInput, byte statusOutput) {
  byte sensor;
  digitalWrite(DPIN_MUX_S0, bitRead(sensorInput, 0));
  digitalWrite(DPIN_MUX_S1, bitRead(sensorInput, 2));
  digitalWrite(DPIN_MUX_S2, bitRead(sensorInput, 1));
  int sensorReading = analogRead(APIN_MUX_OUT);
  if (sensorReading < 400) {
    sensor = SENSOR_SHORT;
    sensorStatus.set(statusOutput);
    fault = true;
  } 
  else if (sensorReading >= 400 && sensorReading <= 590) {
    sensor = SENSOR_NORMAL;
    sensorStatus.clear(statusOutput);
  } 
  else if (sensorReading >= 590 && sensorReading <= 800) {
    sensorStatus.set(statusOutput);
    if (systemState >= STATE_ARMED) {
      sensor = SENSOR_TRIPPED;
      if (systemState < STATE_ALERTING) {
        systemState = STATE_TRIPPED;
      }
      if (alertMillis == 0) { 
        alertMillis = millis();
      }
    } 
  } 
  else {
    sensor = SENSOR_OPEN;
    sensorStatus.set(statusOutput);
    fault = true;
  }
  return sensor;
}

//------------------------------------------------------------------------------
/* Retrieves the current status of the system switches.
 */
void checkSwitches() {
  switches.readBuffer();
  
  silentMode = (switches.readPin(SETTINGS_DIP_SILENT_ENABLE) == HIGH);
  
  int maintSwitch = switches.readPin(SETTINGS_DIP_MAINT_ENABLE);
  if (maintSwitch == HIGH) {
    maintEnabled |= (systemState == STATE_UNARMED) && (maintSwitch == HIGH);
  } else {
    maintEnabled = false;
  }
  
  if (maintEnabled) {
    if (millis() > maintModeMillis + 500) {
      maintModeMillis = millis();
      if (digitalRead(DPIN_MAINT_MODE) == HIGH) {
        maintMode = (++maintMode) % MAX_MAINT_MODES;
        if (maintMode == MAINT_MODE_ARMING_TIMEOUT) {
          sprintf(keypad, "%d", armingTimeout);
          keypadPos = strlen(keypad);
        } else if (maintMode == MAINT_MODE_ALERT_TIMEOUT) {
          sprintf(keypad, "%d", alertTimeout);
          keypadPos = strlen(keypad);
        } else if (maintMode == MAINT_MODE_KEYPAD_TIMEOUT) {
          sprintf(keypad, "%d", keypadTimeout);
          keypadPos = strlen(keypad);
        } else {
          keypad[keypadPos = 0] = '\0';
        }
      }
    }
  } else {
    maintMode = DEFAULT_MAINT_MODE;
  }
}

//------------------------------------------------------------------------------
/* Analyzes the current system state given the state of sensors and keypad
 * input.
 */
 void checkSystemState() {
  if (keyAvailable && (!maintEnabled || (maintMode == DEFAULT_MAINT_MODE))) {
    #ifdef DEBUG
      Serial.print("keypad = [");
      Serial.print(keypad);
      Serial.print(",");
      Serial.print(allowedPasskey);
      Serial.print(",");
      Serial.print(strcmp(keypad, allowedPasskey));
      Serial.println("]");
    #endif
    if (strcmp(keypad, allowedPasskey) == 0) {
      #ifdef DEBUG
        Serial.println("Key matches");
      #endif
      if (systemState > STATE_UNARMED) {
        systemState = STATE_UNARMED;
        systemMillis = 0;
        kpd.clear(KEYPAD_LED_ARMED);
        alertMillis = 0;
        fault = false;
      } 
      else if (systemState == STATE_UNARMED) {
        systemState = STATE_ARMING;
        systemMillis = millis();
      }
    }
    keypad[keypadPos = 0] = '\0';
    keyAvailable = false;
    #ifdef DEBUG
      Serial.print("systemState = [");
      Serial.print(systemState, DEC);
      Serial.println("]");
    #endif
  } 
  else if ((!maintEnabled) &&(millis() > keyMillis + (keypadTimeout * 1000))) {
    keyMillis = 0;
    keypad[keypadPos = 0] = '\0';
  }

  if (systemState >= STATE_ARMED) {
    kpd.set(KEYPAD_LED_ARMED);
    systemMillis = 0;
    if (systemState < STATE_ALERTING) {
      if (alertMillis > 0 && (millis() > alertMillis + (alertTimeout * 1000))) {
        systemState = STATE_ALERTING;
      }
    }
  } 
  else if (systemState == STATE_ARMING) {
    if (millis() > systemMillis + (armingTimeout * 1000)) {
      systemState = STATE_ARMED;
    }
    systemLED = !systemLED;
    kpd.write(KEYPAD_LED_ARMED, systemLED);
  }
  
  if (fault) {
    systemState = STATE_FAULT;
  }
}

//------------------------------------------------------------------------------
/* Retrieves a setting from EEPROM, applying a default value if the given 
 * setting is undefined (0x00 byte).
 */
byte getSetting(int addr, byte defaultValue) {
  byte value = EEPROM.read(addr);
  #ifdef DEBUG
    Serial.print("EEPROM<");
    Serial.print(addr);
    Serial.print("> = [");
    Serial.print(value);
    Serial.println("]");
  #endif
  return (value > 0) ? value : defaultValue;
}

//------------------------------------------------------------------------------
/* Updates all messages to the LCD.
 */
void updateLCD() {
  
  // update time
  lcd.setCursor(0, 0);
  DateTime now = RTC.now();
  sprintf(buffer, "%02u/%02u/%02u", now.month(), now.day(), now.year());
  lcd.print(buffer);
  lcd.setCursor(12, 0);
  sprintf(buffer, "%02u:%02u:%02u", now.hour(), now.minute(), now.second());
  lcd.print(buffer);
  
  // update state
  lcd.setCursor(0, 1);
  if (systemState == STATE_UNARMED) {
    lcd.print("UNARMED  ");
  } else if (systemState == STATE_ARMING) {
    lcd.print("ARMING   ");
  } else if (systemState == STATE_ARMED) {
    lcd.print("ARMED   ");
  } else if (systemState == STATE_TRIPPED) {
    lcd.print("TRIPPED ");
  } else if (systemState == STATE_ALERTING) {
    lcd.print("ALERTING");
  } else if (systemState == STATE_FAULT) {
    lcd.print("<FAULT> ");
  } else {
    lcd.print("         ");
  }

  // update keypad data w/ possible labels for maintenance mode
  lcd.setCursor(0, 2);
  if (maintEnabled && (maintMode != DEFAULT_MAINT_MODE)) {
    lcd.print(modes[maintMode]);
    lcd.print(" = ");
    for (int i = 0; i < MAX_KEY_LENGTH; i++) {
      lcd.print((i < keypadPos) ? keypad[i] : ' ');
    }
  } else {
    for (int i = 0; i < 20; i++) {
      lcd.print((i < keypadPos) ? '*' : ' ');
    }
  }

  // update modes
  lcd.setCursor(18, 3);
  lcd.print((silentMode) ? "S" : " ");
  lcd.print((maintEnabled) ? "M" : " ");

  // update switches
  #ifdef DEBUG
    lcd.setCursor(12, 2);
    for (int i = 0; i<8; i++) {
      lcd.print(switches.readPin(i));
    }
  #endif
 
}
