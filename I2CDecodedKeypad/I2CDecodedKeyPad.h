#ifndef I2CDecodedKeyPad_h
#define I2CDecodedKeyPad_h

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

#include <inttypes.h>
#include "WProgram.h"

class I2CDecodedKeypad {

  private: 
    static char charSet[17];
    char    _buzzAddr;
    char    _keypadAddr;
    int     _decoderDataAvailable;
    int     _rawKey;
    int     _useBeep;
    uint8_t _buffer;
    uint8_t _mask;

  public:
    I2CDecodedKeypad(int kAddr, uint8_t mask = B11111111, int bAddr = -1);
    void beep(int on, int off, int reps);
    void beepOn(void);
    void beepOff(void);
    void clear(uint8_t pin);
    void clearBuffer();
    char getKeyStroke();
    int  getRawKey();
    void init(void);
    void set(uint8_t pin);
    void setBuffer();
    void write(uint8_t pin, bool state);
    void writeBuffer();

  private:
    void i2cWrite(int data);
    int  i2cRead();
};	

#endif
