/*
 *  Simple gamma spectrometer based on an Arduino MEGA 2650. DEC-2020/JAN-2021, Bernd Ulmann.
 *  
 *   This program is the digital part of my rather simple homebrew gamma spectrometer which 
 *  consists of a (commercial) HV power supply, a photomultiplier tube with scintillator
 *  crystal, an analog front end (also described in the project directory), and an Arduino
 *  MEGA 2650 with a 1.8 inch TFT display, a 10 position BCD switch, and a rotary three
 *  position mode control switch.
 *  
 *   The analog front end consists of an input stage which can operate in inverting or
 *  non-inverting mode (so it is possible to used PMTs with the anode at HV or with cathode
 *  at -HV). This is followed by a peak-hold stage which feeds a comparator with adjustable
 *  threshold and an output amplifier with adjustable gain. The comparator generates a 
 *  trigger signal which is fed to the Arduino and causes one analog-digital-conversion of
 *  10 bits.
 *  
 *   This little program controls the overall operation of the spectrometer. In run mode,
 *  data is gathered at every interrupt, in halt mode data gathering is suspended and when
 *  reset is selected the data stored and the display is cleared. 
 *  
 *   The display shows a graph of the energy spectrum which can be scaled along the y-axis
 *  by means of a 10 position BCD switch. The value selected is used to shift the y-data 
 *  bitwise to the right. When the BCD switch setting is changed, the screen is cleared and
 *  the data collected so far is redrawn with the new y-axis scale factor.
 *  
 *   The system can also be controlled via the serial line over the USB-port. Three commands
 *  are supported (with no line ending!): 
 *  
 *  'c': Return the current state of counter and max. Counter is the number of events counted
 *       since the last reset while max is the maximum value of counts in the 1024 energy bins.
 *  'x': Reset the system - this clears all stored data as well as the display.
 *  'r': Read all values collected so far. These are returned as a \n separated list of 
 *       1024 entries.
 */

#include <Adafruit_GFX.h>    // Core graphics library
#include <Adafruit_ST7735.h> // Hardware-specific library for ST7735
#include <SPI.h>

#define TFT_CS         3                    // TFT-display chip select line is connected to output line 3.
#define TFT_RST        5                    // TFT-display reset line is connected to output line 5.
#define TFT_DC         4                    // TFT-display data/command control line is connected to output line 4.
#define TFT_WIDTH    128                    // Many things in the code rely on 128 columns of the display! Sometimes hardcoded! Beware!

#define LEVELS      1024                    // Energy levels distinguished - using the on-chip ADC 10 bits or resultion can be obtained.

#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit)) // Clear bit to control the ADC conversion speed.
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))  // Set bit to control the ADC conversion speed.

#define STATE_RUN   9                       // These values are defined by the connections of the mode switch to PORTH.
#define STATE_HALT  10                      // The software basically implements a trivial state machine controlling
#define STATE_RESET 3                       // the mode of operation, based on these three possible states.

volatile unsigned long counter = 0,         // How many impulses have been counted so far?
                       max = 0,             // Which is the maximum number of counts in a energy level?
                       data[LEVELS],        // Raw data is stored in this 1024 entry array.
                       display[TFT_WIDTH];  // Since the display is more narrow than 1024 we need energy bins which are stored here.
unsigned int yscale = 0,                    // Scaling factor (2 ** n) for the y-axis.
             state = STATE_RUN;             // Current state of the system.

Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_RST); // Global TFT-object

void setup() {
  /*
  ** Port allocation:
  ** ------------------------------------
  ** PH4      OUT ISR-LED
  ** PH3      IN  Reset switch
  ** PE3      OUT TFT reset
  ** PG5      OUT TFT data/command
  ** PE5      OUT TFT chip select
  ** PE4      IN  External interrupt line
  ** PE1      OUT TXD0 (unused)
  ** PE0      IN  RXD0 (unused)
  ** PH0      IN  Halt switch
  ** PH1      IN  Run switch
  ** PD0-PD3  IN  Divider BCD switch
  */

  DDRD = B00000000;
  DDRE = B00101010;
  DDRG = B00100000;
  DDRH = B00010000;
  
  tft.initR();
  tft.fillScreen(ST77XX_BLACK);

  /*
  ** Decrease the ADC conversion time:
  **
  ** Prescale ADPS2 ADPS1 ADPS0 Clock freq (MHz)  Sampling rate (KHz)
  ** ----------------------------------------------------------------
  ** 2         0     0     1     8                 615
  ** 4         0     1     0     4                 307
  ** 8         0     1     1     2                 153
  ** 16        1     0     0     1                 76.8
  ** 32        1     0     1     0.5               38.4
  ** 64        1     1     0     0.25              19.2
  ** 128       1     1     1     0.125             9.6
  */

  sbi(ADCSRA, ADPS2);
  cbi(ADCSRA, ADPS1);
  sbi(ADCSRA, ADPS0);

  PORTH = B00010000;      // Turn the trigger LED of if it was on
  Serial.begin(115200);
  reset();
}

/*
**  This is the central interrupt service routine. Each event detected by the analog
** front end causes this routine to be triggered. The routine performs a single analog
** digital conversion and increments the data and display values accordingly. It also
** updates the graph shown on the display.
 */
void triggered() {
  PORTH = B00000000;      // Switch on the trigger LED
  counter++;

  int value = analogRead(A0);
  if (++data[value] > max)
    max = data[value];

  value >>= 3;            // Basically we divide the energy which can have 2^{10} levels by 8 for the display
  display[value]++;

  tft.drawPixel(TFT_WIDTH - value, display[value] >> yscale, ST77XX_WHITE);

  PORTH = B00010000;      // Switch trigger LED off
}

/*
** Reset the system. This clears all data gathered so far and clears the display, too.
 */
void reset() {
  detachInterrupt(0);
  tft.fillScreen(ST77XX_BLACK);
  counter = max = 0;
  for (int i = 0; i < LEVELS; data[i++] = 0);
  for (int i = 0; i < TFT_WIDTH; display[i++] = 0);
  Serial.print("RESET\n");

  if (state == STATE_RUN)
    attachInterrupt(0, triggered, FALLING);
}

/*
**  Whenever the y-scale factor changes, this routine is called to redraw the graph 
** shown on the display with the new y-scale factor in effect.
 */
void redraw() { // Redraw the screen after a change of the y-scale factor
  detachInterrupt(0);
  tft.fillScreen(ST77XX_BLACK);
  for (int i = 0; i < TFT_WIDTH; i++)
    tft.drawFastVLine(TFT_WIDTH - i, 0, display[i] >> yscale, ST77XX_WHITE);

  if (state == STATE_RUN)
    attachInterrupt(0, triggered, FALLING);
}

/*
** This is the main program loop.
 */
void loop() {
  unsigned int control, yscale_switch;

  for (;;) {                            // This is a tad faster then relying on the implicit loop() activation.
    yscale_switch = 15 - (PIND & 0x0f); // Read the yscale BCD encoder switch.
    control = PINH & B00001011;         // Read the mode switch: 9 -> RUN, 10 -> HALT, 3 -> RESET

    if (control == STATE_RUN && state != STATE_RUN) {             // Mode has been changed to run.
      state = STATE_RUN;
      attachInterrupt(0, triggered, FALLING);
    } else if (control == STATE_HALT && state != STATE_HALT) {    // Mode has been changed to halt.
      state = STATE_HALT;
      detachInterrupt(0);
    } else if (control == STATE_RESET && state != STATE_RESET) {  // Mode has been changed to reset.
      state = STATE_RESET;
      reset();
    }
    
    if (yscale_switch != yscale) {  // y-scale switch setting has been changed
      yscale = yscale_switch;
      redraw();
    }

    if (Serial.available() > 0) {   // A command has been sent via the serial line.
      switch (Serial.read()) {
        case 'c': // Read counter
          detachInterrupt(0);
          Serial.print("Counter = " + String(counter) + ", maximum = " + String(max) + "\n");
          attachInterrupt(0, triggered, FALLING);
          break;
        case 'r': // Readout
          detachInterrupt(0);
          Serial.print("---------------------------\n");
          for (int i = 0; i < LEVELS; Serial.print(String(data[i++]) + "\n"));
          Serial.print("---------------------------\n");
          attachInterrupt(0, triggered, FALLING);
          break;
        case 'x': // Reset
          reset();
          break;
        default:
          Serial.print("?\n");
      }
    }
  }
}
