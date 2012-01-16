_This security system is a work-in-progress._ 

## BACKGROUND

I find myself needing a comprehensive security system that notifies me of incursions (or excursions) especially at night without first resorting to sirens. This notification should take multiple forms including the traditional sirens as well as Twitter or SMS. I want full control over the system and do not want to pay someone a monthly monitoring fee. I want to be able to monitor key characteristics such as temperature, humidity, water on the basement floor, etc.

## OVERVIEW
This system will be built upon the Arduino open source hardware platform. It will use one Arduino (probably an [RBBB](http://shop.moderndevice.com/products/rbbb-kit) from Modern Device) to manage all sensors, keypads, and LCDs. It will use a second conventional Arduino with the Ethernet Shield for notification and secured control. The two Arduinos will commmunicate with each other using a messsaging framework over the I2C bus.

### Sensor Controller
TBD

### Communications Controller
TBD

## RESOURCES
TBD
