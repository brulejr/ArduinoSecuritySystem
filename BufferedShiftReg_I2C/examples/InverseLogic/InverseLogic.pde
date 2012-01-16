/**
  Example of using BufferedShiftReg_I2C with its legic inverter - 
  Flashes six LEDs in sequence, the first three (P0 - P2) are 
  off-turning-on whereas the second three (P3 - P5) are 
  on-turning-off. 
  
  The PCF8574, around which this library is built, sinks current 
  (versus sourcing it). As a result, LEDs are typically connected to
  a 5v supply with a current-limiting resistor. This approach causes 
  inverted logic to be applied when no additional circuitry is used. 
  A bit value of one (1) cause the corresponding LED to be darkened.
  
  The bitmask passed when constructing the shift register indicate
  that inverse logic is to be used with the three least-significant
  bits. This results in those LEDs being off (cleared) until on 
  (set).

  Copyright (C) 2012 Jon Brule  All rights reserved.

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  See file LICENSE.txt for further informations on licensing terms.

*/
#include <Wire.h>
#include <BufferedShiftReg_I2C.h>

#define SR_I2C_ADDR 0x38
#define MAX_LEDS 6

BufferedShiftReg_I2C shiftreg(SR_I2C_ADDR, B11111000);

int cnt = 0;

void setup() {
  Wire.begin();
}

void loop() {
  shiftreg.clearBuffer();
  shiftreg.set(cnt++);
  shiftreg.writeBuffer();
  if (cnt == MAX_LEDS) { cnt = 0; }
  delay(100);
}
