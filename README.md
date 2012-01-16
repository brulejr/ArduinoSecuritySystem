_This security system is a work-in-progress._ 

## ARDUINO SECURITY SYSTEM

### BACKGROUND

I find myself needing a comprehensive security system that notifies me of incursions (or excursions) especially at night without first resorting to sirens. This notification should take multiple forms including the traditional sirens as well as Twitter or SMS. I want full control over the system and do not want to pay someone a monthly monitoring fee. I want to be able to monitor key characteristics such as temperature, humidity, water on the basement floor, etc.

### OVERVIEW
This system will be built upon the Arduino open source hardware platform. It will use one Arduino (probably an [RBBB](http://shop.moderndevice.com/products/rbbb-kit) from Modern Device) to manage all sensors, keypads, and LCDs. It will use a second conventional Arduino with the Ethernet Shield for notification and secured control. The two Arduinos will commmunicate with each other using a messsaging framework over the I2C bus.

#### Sensor Controller
TBD

#### Communications Controller
TBD

## LIBRARIES
The following libraries naturally grew out of developing the _Adruino Security System_.

### BufferedShiftReg_I2C
Digital pins are a premium on an Arduino. As a result, often shift registers such as the [75HC595](http://www.sparkfun.com/datasheets/IC/SN74HC595.pdf) are used to reduce the pin count. Each 75HC595 uses three digital pins to create eight digital outputs. Multiple chips may be ganged together to create even more pin savings.
Wouldn't it be nice if the same outputs could be created without consuming any Arduino digital pins? By connecting a [PCF8574](http://www.nxp.com/documents/data_sheet/PCF8574.pdf) to the I2C bus (Analog pins 4 and 5), and using this library, an I2C-based shift register is created.
