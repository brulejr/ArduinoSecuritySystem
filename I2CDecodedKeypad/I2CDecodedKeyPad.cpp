/* I2C DecodedKeypad
 * 
 * Library for interfacing to keypad using an I2C bus and a 74C922 
 * keypad decoder
 *
 * Copyright (c) 2009, A. Davison (software@davison-family.com)
 * All rights reserved.
 *
 * Source contributions from i2ckeypad by Angel Sancho (angelitodeb@gmail.com)
 *
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
 *  This library interfaces to a 4x4 keypad which has been decoded using
 *  a 74C922 keypad decoder, and then serialised using the PCF8574 I2C bus 
 *  expander.
 *
 *  Wiring diagrams for for the circuit can be found under the "hardware" 
 *  folder, along with a PDF circuit board design.
 *
 *  IMPORTANT! You have to call Wire.begin() before init() in your code
 *
 */

#include "I2CDecodedKeypad.h"
#include <Wire.h>

extern "C" {
  #include "WConstants.h"
}

#define KBDADDR (0x4<<3|0x7)

char I2CDecodedKeypad::charSet[17] = "123A456B789C*0#D";

I2CDecodedKeypad::I2CDecodedKeypad(int kAddr, uint8_t mask, int bAddr) {
  _keypadAddr = kAddr;
  _mask = mask;
  _buzzAddr = bAddr;
  _decoderDataAvailable = 0;
  _useBeep = 1;
  if (_buzzAddr == -1) {
    _useBeep = 0;
  }
}

char I2CDecodedKeypad::getKeyStroke() {
  _rawKey = i2cRead();

  // OK. A key has been pressed and released, so return the value.
  if ((_decoderDataAvailable == 1) && ((_rawKey & 0x10) == 0)) {
    _rawKey &= 0x0F;
    if (_rawKey == 14) {
      beep(25, 25, 2);
    } else {
      beep(25, 00, 1);
    }
    _decoderDataAvailable = 0;
    return charSet[_rawKey];
  } else if ((_rawKey & 0x10) > 0) {
    _decoderDataAvailable = 1;
  }

  // Otherwise nothing happened...
  return 0;
}

int I2CDecodedKeypad::getRawKey() {
  return _rawKey;
}

void I2CDecodedKeypad::beep(int on, int off, int reps) {
  if (_useBeep > 0) {
    while (reps > 0) {
      digitalWrite(_buzzAddr,HIGH);
      delay(on);
      digitalWrite(_buzzAddr,LOW);
      delay(off);
      reps--;
    }
  }
}

void I2CDecodedKeypad::init(void) {
  i2cWrite(0x1f);
  if (_buzzAddr >= 0) {
    pinMode(_buzzAddr,OUTPUT);
  }
}	

//
// Clears the given bit within the buffer
//
void I2CDecodedKeypad::clear(uint8_t bit) {
  if (bitRead(_mask, bit)) {
    bitClear(_buffer, bit);
  } else {
    bitSet(_buffer, bit);
  }
}

//
// Sets the given bit within the buffer
//
void I2CDecodedKeypad::set(uint8_t bit) {
  if (bitRead(_mask, bit)) {
    bitSet(_buffer, bit);
  } else {
    bitClear(_buffer, bit);
  }
}

//
// Writes the given bit to the buffer
//
void I2CDecodedKeypad::write(uint8_t bit, bool state) {
  if (state) {
    set(bit);
  } else {
    clear(bit);
  }
}

//
// Clears all buffer bits
//
void I2CDecodedKeypad::clearBuffer() {
  _buffer = _mask ^ B11111111;
}

//
// Sets all buffer bits
//
void I2CDecodedKeypad::setBuffer() {
  _buffer = _mask;
}

//
// Writes the buffer to the I2C shift register
//
void I2CDecodedKeypad::writeBuffer() {
  Wire.beginTransmission(_keypadAddr);
  Wire.send(_buffer | B00011111);
  Wire.endTransmission();
}

void I2CDecodedKeypad::i2cWrite(int data) {
  Wire.beginTransmission(_keypadAddr);
  Wire.send(data);
  Wire.endTransmission();
}

int I2CDecodedKeypad::i2cRead() {
  Wire.requestFrom(_keypadAddr,1);
  return Wire.receive();
}

void I2CDecodedKeypad::beepOn(void) {
  _useBeep = 1;
}

void I2CDecodedKeypad::beepOff(void) {
  _useBeep = 0;
}

