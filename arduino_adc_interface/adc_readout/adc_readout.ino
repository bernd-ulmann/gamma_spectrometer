/*
    This program controls a Mega 2650 board connected to a Nuclear Data ND580 ADC.
    The purpose is to setup a simple gamma spectroscopy system consisting of old
    NIM modules and this readout module.

    Port mapping (signals marked with '*' are active low):

    IO    Function  Dir.  SUBD  Pinheader inside ADC
    ------------------------------------------------
    PA0   D0*       IN    1     14
    PA1   D1*       IN    2     16
    PA2   D2*       IN    3     18
    PA3   D3*       IN    4     20
    PA4   D4*       IN    5     22
    PA5   D5*       IN    6     24
    PA6   D6*       IN    7     26
    PA7   D7*       IN    8     15
    PC0   D8*       IN    9     17
    PC1   D9*       IN    10    19
    PC2   D10*      IN    11    21
    PC3   D11*      IN    12    23
    PC4   D12*      IN    13    25
    PC5   Inhibit*  IN    20    12
    TXD1  READY*    IN    14    10
    PB0   ACCEPT*   OUT   17    2
    GND   ENABLE*         18    8
    GND   OUT ENA*        22    4
    GND   GND             24    1, 3, 5, 7, 9, 11

    05-APR-2022 B. Ulmann Initial implementation
    08-APR-2022 B. Ulmann Added maximum output in 'c'-command
    03-SEP-2023 B. Ulmann Added X/Y-output for an oscilloscope
*/

#define BAUD_RATE 115200
#define READY_PIN 18
#define INT_MODE  FALLING
#define ADC_BITS  11        // 2k resolution - we don't have enough RAM for 12 bits resolution :-(

#define X_PIN 13            // PWM outputs for X and Y oscilloscope inputs.
#define Y_PIN 4
#define PIXEL_DELAY 80      // Delay after plotting a pixel to get a more stable display.

/*  The X/Y display requires two RC combinations connected to pins 13 and 4 of the 
 * MEGA 2650 board. 4k7 and 100 nF are suggested to get a relatively stable display
 */

union {
  byte raw[2];
  uint16_t value;
} data;

uint16_t counters[1 << ADC_BITS];
uint32_t events = 0, maximum = 0;

void get_data() {
  byte low_byte, high_byte;
  
  detachInterrupt(digitalPinToInterrupt(READY_PIN));

  data.raw[0] = PINA;
  data.raw[1] = PINC & B00111111;

  uint16_t address = ~data.value & 0x0FFF;

  if (counters[address] != 65535)
    if (++counters[address] > maximum)
      maximum = counters[address];

  events++;

  if (!(events % 10000))  // Print a dot every 10000 values to show its alive
    Serial.print(".");
  
  PORTB = B00000000;  // Flip ACCEPT*
  PORTB = B00000001;

  attachInterrupt(digitalPinToInterrupt(READY_PIN), get_data, INT_MODE);
}

void setup() {
  DDRA = B00000000;   // Lower eight bits
  DDRB = B00000001;   // PB0 is an output
  DDRC = B00000000;   // Upper five bits + inhibit

  PORTB = B00000001;  // Deactivate ACCEPT*

  Serial.begin(BAUD_RATE);

  pinMode(X_PIN, OUTPUT);
  pinMode(Y_PIN, OUTPUT);
  TCCR0B = (TCCR0B & 0b11111000) | 0x01;  // No clock divider for timer 0 to get a high PWM frequency

  attachInterrupt(digitalPinToInterrupt(READY_PIN), get_data, INT_MODE);

  Serial.print("INIT...\n");
}

void loop() {
  unsigned int x = 0, y_scale = 0;

  for (;;) {
    analogWrite(X_PIN, x);
    analogWrite(Y_PIN, counters[x++ << 3] >> y_scale);

    delayMicroseconds(PIXEL_DELAY);
    if (x == 256) {
      x = 0;
      analogWrite(X_PIN, x);

      delayMicroseconds(1000);  // Wait pretty long for the beam to get back to the lower left corner.

      int flag = 0;             // Do we need to rescale the display?
      for (unsigned int i = 0; i < 256; i++)
        if ((counters[i << 3] >> y_scale) > 255)
          flag = 1;

      if (flag) y_scale++;      // Scale by another factor of 2.
    }

    if (Serial.available() > 0) {
      switch(Serial.read()) {
        case 'c': // Read counter
          detachInterrupt(digitalPinToInterrupt(READY_PIN));
          Serial.print("Events = " + String(events) + ", maximum value = " + String(maximum) + "\n");
          attachInterrupt(digitalPinToInterrupt(READY_PIN), get_data, INT_MODE);
          break;
        case 'r': // Readout
          detachInterrupt(digitalPinToInterrupt(READY_PIN));
          Serial.print("--------\n");
          for (uint16_t i = 0; i < (1 << ADC_BITS); Serial.print(String(counters[i++]) + "\n"));
          Serial.print("--------\n");
          attachInterrupt(digitalPinToInterrupt(READY_PIN), get_data, INT_MODE);
          break;
        case 'x': // Reset
          detachInterrupt(digitalPinToInterrupt(READY_PIN));
          events = maximum = y_scale = 0;
          for (uint16_t i = 0; i < (1 << ADC_BITS); counters[i++] = 0);
          Serial.print("Reset\n");
          attachInterrupt(digitalPinToInterrupt(READY_PIN), get_data, INT_MODE);
          break;        
      }
    }
  }
}

