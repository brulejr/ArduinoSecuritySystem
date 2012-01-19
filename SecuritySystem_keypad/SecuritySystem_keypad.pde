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

#include <TimerOne.h> 
#include <Wire.h>
#include <BufferedShiftReg_I2C.h>
#include <I2CDecodedKeyPad.h>
#include "RTClib.h"

#define STATE_SHORT 0
#define STATE_NORMAL 1
#define STATE_TRIPPED 2
#define STATE_OPEN 3

#define STATE_UNARMED 0
#define STATE_ARMING 1
#define STATE_ARMED 2

#define DPIN_MUX_S0 8
#define DPIN_MUX_S1 9
#define DPIN_MUX_S2 10

#define DPIN_SIREN 11

#define APIN_MUX_OUT 0

#define MP_SENSOR_A 0
#define MP_SENSOR_B 1

#define ARMING_INTERVAL 5000
#define LED_ARMED_BLINK_INTERVAL 500
#define SIREN_INTERVAL 5000

#define SR_I2C_ADDR 0x39
#define SR_LED_FAULT 0
#define SR_LED_ARMED 1
#define SR_LED_A 2
#define SR_LED_B 3
#define SR_SIREN 7

// With A0, A1 and A2 of PCF8574 to ground I2C address is 0x20
// With A0, A1 and A2 of PCF8574A to ground I2C address is 0x38
#define KEYPAD_I2C_ADDR 0x38
#define MAX_KEY_LENGTH 4
#define KEYPAD_TIMEOUT 15000

BufferedShiftReg_I2C shiftreg(SR_I2C_ADDR, B00000000);
RTC_DS1307 RTC;

// keypad handling variables
I2CDecodedKeypad kpd(KEYPAD_I2C_ADDR);
long keyMillis = 0;
bool keyAvailable = false;
int passkeyPos = 0;
char allowedPasskey[MAX_KEY_LENGTH+1] = { 
  '1','2','3','4','\0' };
char passkey[MAX_KEY_LENGTH+1] = { 
  '\0' };

// arming state variables
bool fault;
long armedMillis = 0;
byte armedState = STATE_UNARMED;
bool armedLED = false;

// siren state variables
bool siren = false;
long sirenMillis = 0;

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

  // initialize clock device
  Wire.begin();
  RTC.begin();
  //if (! RTC.isrunning()) {
  //  Serial.println("RTC is NOT running!");
  //  RTC.adjust(DateTime(__DATE__, __TIME__));
  //}

  // clear the shift register
  shiftreg.clearBuffer();

  // initialize timer1 interrupt
  Timer1.initialize(250000);
  Timer1.attachInterrupt(timerOneCallback);

  // initialize keypad device
  kpd.init();

}

//------------------------------------------------------------------------------
/* Main Loop: Monitor the Security System sensors.
 */
void loop() {
  checkKeypad();
  fault = false;
  checkSensor(MP_SENSOR_A, SR_LED_A);
  checkSensor(MP_SENSOR_B, SR_LED_B);
  shiftreg.write(SR_LED_FAULT, fault);
  shiftreg.writeBuffer();
}

//------------------------------------------------------------------------------
/* Handle monitoring analysis logic
 */
void timerOneCallback(void) {    // timer compare interrupt service routine
  checkArmedState();
  siren = (sirenMillis > 0 && (millis() > sirenMillis + SIREN_INTERVAL));
  //shiftreg.write(SR_SIREN, siren);
  digitalWrite(DPIN_SIREN, siren);
}

//------------------------------------------------------------------------------
/*
 */
void checkArmedState() {
  if (keyAvailable) {
    Serial.print("passkey = [");
    Serial.print(passkey);
    Serial.print(",");
    Serial.print(allowedPasskey);
    Serial.print(",");
    Serial.print(strcmp(passkey, allowedPasskey));
    Serial.println("]");
    if (strcmp(passkey, allowedPasskey) == 0) {
      Serial.println("Key matches");
      if (armedState == STATE_ARMED || armedState == STATE_ARMING) {
        armedState = STATE_UNARMED;
        armedMillis = 0;
        shiftreg.clear(SR_LED_ARMED);
        sirenMillis = 0;
      } 
      else if (armedState == STATE_UNARMED) {
        armedState = STATE_ARMING;
        armedMillis = millis();
      }
    }
    passkey[passkeyPos = 0] = '\0';
    keyAvailable = false;
    Serial.print("armedState = [");
    Serial.print(armedState, DEC);
    Serial.println("]");
  } 
  else if (millis() > keyMillis + KEYPAD_TIMEOUT) {
    keyMillis = 0;
    passkey[passkeyPos = 0] = '\0';
  }


  if (armedState == STATE_ARMED) {
    shiftreg.set(SR_LED_ARMED);
    armedMillis = 0;
  } 
  else if (armedState == STATE_ARMING) {
    if (millis() > armedMillis + ARMING_INTERVAL) {
      armedState = STATE_ARMED;
    }
    armedLED = !armedLED;
    shiftreg.write(SR_LED_ARMED, armedLED);
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
      Serial.print("(rawkey: ");
      Serial.print(kpd.getRawKey());
      Serial.print(", keyval: ");
      Serial.print(k, BYTE);
      Serial.print(", passkey: ");
      Serial.print(passkey);
      Serial.println(")");
    }
  }
}

//------------------------------------------------------------------------------
/* Checks the state of the given sensor
 */
byte checkSensor(byte sensorInput, byte statusOutput) {
  byte state;
  digitalWrite(DPIN_MUX_S0, bitRead(sensorInput, 0));
  digitalWrite(DPIN_MUX_S1, bitRead(sensorInput, 2));
  digitalWrite(DPIN_MUX_S2, bitRead(sensorInput, 1));
  int sensorReading = analogRead(APIN_MUX_OUT);
  if (sensorReading < 400) {
    state = STATE_SHORT;
    if (armedState == STATE_ARMED) {
      shiftreg.set(statusOutput);
    } 
    else {
      shiftreg.clear(statusOutput);
    }
    fault = true;
  } 
  else if (sensorReading >= 400 && sensorReading <= 590) {
    state = STATE_NORMAL;
    shiftreg.clear(statusOutput);
  } 
  else if (sensorReading >= 590 && sensorReading <= 800) {
    if (armedState == STATE_ARMED) {
      state = STATE_TRIPPED;
      shiftreg.set(statusOutput);
      if (sirenMillis == 0) { 
        sirenMillis = millis();
      }
    } 
    else {
      shiftreg.clear(statusOutput);
    }
  } 
  else {
    state = STATE_OPEN;
    if (armedState == STATE_ARMED) {
      shiftreg.set(statusOutput);
    } 
    else {
      shiftreg.clear(statusOutput);
    }
    fault = true;
  }
  return state;
  DateTime now = RTC.now();
  if (armedState == STATE_ARMED) {
    Serial.print("ARMED - ");
  } 
  else if (armedState == STATE_ARMING) {
    Serial.print("ARMING - ");
  } 
  else {
    Serial.print("UNARMED - ");
  }
  Serial.print(sensorInput, DEC);
  Serial.print(": ");
  Serial.print(sensorReading, DEC);
  Serial.print(" (");
  Serial.print(state, DEC);
  Serial.print(") - ");
  Serial.print(now.year(), DEC);
  Serial.print('/');
  Serial.print(now.month(), DEC);
  Serial.print('/');
  Serial.print(now.day(), DEC);
  Serial.print(' ');
  Serial.print(now.hour(), DEC);
  Serial.print(':');
  Serial.print(now.minute(), DEC);
  Serial.print(':');
  Serial.print(now.second(), DEC);
  Serial.println();  

  return state;
}
