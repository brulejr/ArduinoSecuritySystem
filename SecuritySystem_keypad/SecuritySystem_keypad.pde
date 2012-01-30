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
 */

// configurable options (uncomment to enable)
//#define RESET_CLOCK
//#define RESET_PARMS
//#define DEBUG

// library includes
#include <TimerOne.h> 
#include <Wire.h>
#include <BufferedShiftReg_I2C.h>
#include <I2CDecodedKeyPad.h>
#include <LiquidCrystal_I2C.h>
#include <RTClib.h>
#include <EEPROM.h>

#define VERSION "v0.1.4"

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
#define DPIN_PARM_MODE 12

#define APIN_MUX_OUT 0

#define MP_SENSOR_A 0
#define MP_SENSOR_B 1

#define ARMING_TIMEOUT 5
#define ALERT_TIMEOUT 5

#define SR_I2C_ADDR 0x39
#define SR_LED_A 0
#define SR_LED_B 1
#define SR_SIREN 7

// With A0, A1 and A2 of PCF8574 to ground I2C address is 0x20
// With A0, A1 and A2 of PCF8574A to ground I2C address is 0x38
#define KEYPAD_I2C_ADDR 0x38
#define MAX_KEY_LENGTH 4
#define KEYPAD_TIMEOUT 15
#define KEYPAD_LED_FAULT 5
#define KEYPAD_LED_ARMED 6

#define LCD_I2C_ADDR 0x3A

#define SETTINGS_I2C_ADDR 0x3B
#define SETTINGS_DIP_MAINT_MODE 0
#define SETTINGS_DIP_SILENT_MODE 1

#define MAX_PARM_MODES 4
#define EEPROM_ARMING_TIMEOUT 0
#define EEPROM_ALERT_TIMEOUT 1
#define EEPROM_KEYPAD_TIMEOUT 2

// system settings variables
BufferedShiftReg_I2C settings(SETTINGS_I2C_ADDR);

// sensor state variables
BufferedShiftReg_I2C shiftreg(SR_I2C_ADDR, B00000000);

// real-time clock handling variables
RTC_DS1307 RTC;

// keypad handling variables
I2CDecodedKeypad kpd(KEYPAD_I2C_ADDR, B00011111);
long keyMillis = 0;
bool keyAvailable = false;
int passkeyPos = 0;
char allowedPasskey[MAX_KEY_LENGTH+1] = { '1','2','3','4','\0' };
char passkey[MAX_KEY_LENGTH+1] = { '\0' };

// lcd handling variables
LiquidCrystal_I2C lcd(LCD_I2C_ADDR, 20, 4);  // set the LCD for a 20 chars and 4 line display

// system state variables
int alertTimeout;
long alertMillis = 0;
long armedMillis = 0;
byte armedState = STATE_UNARMED;
bool armedLED = false;
int armingTimeout;
bool fault;
int keypadTimeout;
bool maintMode;
int parmMode = 0;
long parmModeMillis = 0;
bool silentMode;

// misc variables
char buffer[20];

//------------------------------------------------------------------------------
/* Initialize the Security System firmware.
 */
void setup() {
  Serial.begin(57600);

  pinMode(13, OUTPUT);

  pinMode(DPIN_MUX_S0, OUTPUT);
  pinMode(DPIN_MUX_S1, OUTPUT);
  pinMode(DPIN_MUX_S2, OUTPUT);

  pinMode(DPIN_SIREN, OUTPUT);
  
  pinMode(DPIN_PARM_MODE, INPUT);

  // initialize clock device
  Wire.begin();
  RTC.begin();
  #ifdef RESET_CLOCK
    if (! RTC.isrunning()) {
      Serial.println("RTC is NOT running!");
      RTC.adjust(DateTime(__DATE__, __TIME__));
    }
  #endif

  // initialize timer1 interrupt
  Timer1.initialize(250000);
  Timer1.attachInterrupt(timerOneCallback);
  
  // initialize settings for reading
  settings.setBuffer();
  settings.writeBuffer();

  // initialize keypad device
  kpd.init();
  kpd.clearBuffer();
  kpd.writeBuffer();

  // clear the shift register
  shiftreg.clearBuffer();
  kpd.writeBuffer();
  
  // initialize parameters
  #ifdef RESET_PARMS
    EEPROM.write(EEPROM_ARMING_TIMEOUT, ARMING_TIMEOUT);
    EEPROM.write(EEPROM_ALERT_TIMEOUT, ALERT_TIMEOUT);
    EEPROM.write(EEPROM_KEYPAD_TIMEOUT, KEYPAD_TIMEOUT);
  #endif
  armingTimeout = getParameter(EEPROM_ARMING_TIMEOUT, ARMING_TIMEOUT) * 1000;
  alertTimeout = getParameter(EEPROM_ALERT_TIMEOUT, ALERT_TIMEOUT) * 1000;
  keypadTimeout = getParameter(EEPROM_KEYPAD_TIMEOUT, KEYPAD_TIMEOUT) * 1000;
  
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
  checkSettings();
  checkKeypad();
  fault = false;
  checkSensor(MP_SENSOR_A, SR_LED_A);
  checkSensor(MP_SENSOR_B, SR_LED_B);
  shiftreg.writeBuffer();
  fault |= (armedState == STATE_FAULT);
  kpd.write(KEYPAD_LED_FAULT, fault);
  kpd.writeBuffer();
  updateLCD();
}

//------------------------------------------------------------------------------
/* Handle monitoring analysis logic
 */
void timerOneCallback(void) {    // timer compare interrupt service routine
  checkSystemState();
  if (!maintMode) {
    digitalWrite(DPIN_SIREN, (!silentMode) && (armedState >= STATE_ALERTING));
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
      passkey[passkeyPos = 0] = '\0';
      keyAvailable = false;
    } 
    else if (k == '#') {
      keyAvailable = true;
    } 
    else {
      if (passkeyPos >= MAX_KEY_LENGTH) {
        for (int i = 0; i < MAX_KEY_LENGTH; i++) {
          passkey[i] = passkey[i + 1];
        }
        passkey[MAX_KEY_LENGTH] = '\0';
        passkeyPos = MAX_KEY_LENGTH - 1;
      }
      passkey[passkeyPos++] = k;
      passkey[passkeyPos] = '\0';
      #ifdef DEBUG
        Serial.print("(rawkey: ");
        Serial.print(kpd.getRawKey());
        Serial.print(", keyval: ");
        Serial.print(k, BYTE);
        Serial.print(", passkey: ");
        Serial.print(passkey);
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
    shiftreg.set(statusOutput);
    fault = true;
  } 
  else if (sensorReading >= 400 && sensorReading <= 590) {
    sensor = SENSOR_NORMAL;
    shiftreg.clear(statusOutput);
  } 
  else if (sensorReading >= 590 && sensorReading <= 800) {
    shiftreg.set(statusOutput);
    if (armedState >= STATE_ARMED) {
      sensor = SENSOR_TRIPPED;
      if (armedState < STATE_ALERTING) {
        armedState = STATE_TRIPPED;
      }
      if (alertMillis == 0) { 
        alertMillis = millis();
      }
    } 
  } 
  else {
    sensor = SENSOR_OPEN;
    shiftreg.set(statusOutput);
    fault = true;
  }
  return sensor;
}

//------------------------------------------------------------------------------
/* Retrieves the current system settings.
 */
void checkSettings() {
  settings.readBuffer();
  
  silentMode = (settings.readPin(SETTINGS_DIP_SILENT_MODE) == HIGH);
  
  int maintSwitch = settings.readPin(SETTINGS_DIP_MAINT_MODE);
  if (maintSwitch == HIGH) {
    maintMode |= (armedState == STATE_UNARMED) && (maintSwitch == HIGH);
  } else {
    maintMode = false;
  }
  
  if (maintMode) {
    if (millis() > parmModeMillis + 250) {
      parmModeMillis = millis();
      if (digitalRead(DPIN_PARM_MODE) == HIGH) {
        parmMode = (++parmMode) % MAX_PARM_MODES;
      }
    }
  } else {
    parmMode = 0;
  }
}

//------------------------------------------------------------------------------
/* Analyzes the current system state given the state of sensors and keypad
 * input.
 */
 void checkSystemState() {
  if (keyAvailable) {
    #ifdef DEBUG
      Serial.print("passkey = [");
      Serial.print(passkey);
      Serial.print(",");
      Serial.print(allowedPasskey);
      Serial.print(",");
      Serial.print(strcmp(passkey, allowedPasskey));
      Serial.println("]");
    #endif
    if (strcmp(passkey, allowedPasskey) == 0) {
      #ifdef DEBUG
        Serial.println("Key matches");
      #endif
      if (armedState > STATE_UNARMED) {
        armedState = STATE_UNARMED;
        armedMillis = 0;
        kpd.clear(KEYPAD_LED_ARMED);
        alertMillis = 0;
        fault = false;
      } 
      else if (armedState == STATE_UNARMED) {
        armedState = STATE_ARMING;
        armedMillis = millis();
      }
    }
    passkey[passkeyPos = 0] = '\0';
    keyAvailable = false;
    #ifdef DEBUG
      Serial.print("armedState = [");
      Serial.print(armedState, DEC);
      Serial.println("]");
    #endif
  } 
  else if (millis() > keyMillis + keypadTimeout) {
    keyMillis = 0;
    passkey[passkeyPos = 0] = '\0';
  }

  if (armedState >= STATE_ARMED) {
    kpd.set(KEYPAD_LED_ARMED);
    armedMillis = 0;
    if (armedState < STATE_ALERTING) {
      if (alertMillis > 0 && (millis() > alertMillis + alertTimeout)) {
        armedState = STATE_ALERTING;
      }
    }
  } 
  else if (armedState == STATE_ARMING) {
    if (millis() > armedMillis + armingTimeout) {
      armedState = STATE_ARMED;
    }
    armedLED = !armedLED;
    kpd.write(KEYPAD_LED_ARMED, armedLED);
  }
  
  if (fault) {
    armedState = STATE_FAULT;
  }
}

//------------------------------------------------------------------------------
/* Retrieves a parameter from EEPROM, applying a default value if the given 
 * parameter is undefined (0x00 byte).
 */
byte getParameter(int addr, byte defaultValue) {
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
  if (armedState == STATE_UNARMED) {
    lcd.print("UNARMED  ");
  } else if (armedState == STATE_ARMING) {
    lcd.print("ARMING   ");
  } else if (armedState == STATE_ARMED) {
    lcd.print("ARMED   ");
  } else if (armedState == STATE_TRIPPED) {
    lcd.print("TRIPPED ");
  } else if (armedState == STATE_ALERTING) {
    lcd.print("ALERTING");
  } else if (armedState == STATE_FAULT) {
    lcd.print("<FAULT> ");
  } else {
    lcd.print("         ");
  }

  // update keypad entry
  lcd.setCursor(20 - MAX_KEY_LENGTH, 2);
  for (int i = 0; i < MAX_KEY_LENGTH; i++) {
    lcd.print((i < passkeyPos) ? '*' : ' ');
  }

  // update modes
  lcd.setCursor(18, 3);
  lcd.print((silentMode) ? "S" : " ");
  lcd.print((maintMode) ? "M" : " ");
  
  // update parm handling
  lcd.setCursor(0, 2);
  if (maintMode) {
    lcd.print("P");
    lcd.print(parmMode);
  } else {
    lcd.print("  ");
  }

  // update settings
  #ifdef DEBUG
    lcd.setCursor(12, 2);
    lcd.print(settings.readPin(0));
    lcd.print(settings.readPin(1));
    lcd.print(settings.readPin(2));
    lcd.print(settings.readPin(3));
    lcd.print(settings.readPin(4));
    lcd.print(settings.readPin(5));
    lcd.print(settings.readPin(6));
    lcd.print(settings.readPin(7));
  #endif
 
}
