/**
  BufferedShiftReg_I2C - Shift Register Library that uses a buffer for controlled
  writes to an I2C shift register.

  Copyright (C) 2012 Jon Brule  All rights reserved.

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  See file LICENSE.txt for further informations on licensing terms.

*/

#include <Wire.h>
#include "BufferedShiftReg_I2C.h"

//
// Constructor
//
BufferedShiftReg_I2C::BufferedShiftReg_I2C(uint8_t srAddr, uint8_t mask) {
  _srAddr = srAddr;
  _mask = mask;
  _buffer = 0;
}

//
// Clears the given bit within the buffer
//
void BufferedShiftReg_I2C::clear(uint8_t bit) {
  if (bitRead(_mask, bit)) {
    bitClear(_buffer, bit);
  } else {
    bitSet(_buffer, bit);
  }
}

//
// Sets the given bit within the buffer
//
void BufferedShiftReg_I2C::set(uint8_t bit) {
  if (bitRead(_mask, bit)) {
    bitSet(_buffer, bit);
  } else {
    bitClear(_buffer, bit);
  }
}

//
// Writes the given bit to the buffer
//
void BufferedShiftReg_I2C::write(uint8_t bit, bool state) {
  if (state) {
    set(bit);
  } else {
    clear(bit);
  }
}

//
// Clears all buffer bits
//
void BufferedShiftReg_I2C::clearBuffer() {
  _buffer = _mask ^ B11111111;
}

//
// Sets all buffer bits
//
void BufferedShiftReg_I2C::setBuffer() {
  _buffer = _mask;
}

//
// Writes the buffer to the I2C shift register
//
void BufferedShiftReg_I2C::writeBuffer() {
  Wire.beginTransmission(_srAddr);
  Wire.send(_buffer);
  Wire.endTransmission();
}
