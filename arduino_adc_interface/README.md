# Arduino based ADC interface
There are quite some professional NIM analog-digital-converters out there which
can be used for hobbyist gamma spectroscopy. The only problem being how to 
interface these devices as they often feature a proprietary interface.

A few weeks ago I got a Nuclear Data ND580 ADC which in fact came from a 
gamma spectroscopy setup. After some research it turned out that many of these 
ADCs seem to use a similar parallel interface. The various data and control
lines are available at a double row pin header within the ADC module and often 
also on a 25 pin SUB-D connector. (Some systems such as the Canberra 1510 only 
feature this 25 pin connector.)

# Interface description
This is how a typical classic ADC for gamma spectroscopy looks like. The flat
ribbon cable connects to the double row pin header on the upper right and 
features a 25 pin SUB-D connector which typically connects to some memory 
unit or computer interface.
![Interface connector](ADC.jpg}
