/*
  BufferedShiftReg_I2C - Shift Register Library that uses a buffer for controlled
  writes to an I2C shift register.

  Copyright (C) 2012 Jon Brule  All rights reserved.

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  See file LICENSE.txt for further informations on licensing terms.
*/

#ifndef BufferedShiftReg_I2C_h
#define BufferedShiftReg_I2C_h

#include <inttypes.h>
#include "WProgram.h"

class BufferedShiftReg_I2C {
  private:
    byte _buffer;
    uint8_t _mask;
    int _srAddr;

  public:
    BufferedShiftReg_I2C(int srAddr, uint8_t mask = B11111111);
    void clear(uint8_t pin);
    void clearBuffer();
    void readBuffer();
    int readPin(uint8_t bit);
    void set(uint8_t pin);
    void setBuffer();
    void write(uint8_t pin, bool state);
    void writeBuffer();
};

#endif

