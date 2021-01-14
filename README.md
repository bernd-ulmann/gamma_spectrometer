# Experiments in Gamma spectroscopy
Gamma spectroscopy is something which always fascinated me, especially since 
I got a wonderful single line Gamma spectrometer made by Siemens in the late
1950s which I 
[repaired and restored](http://www.vaxman.de/projects/gspectrometer/index.html)
during the course of several weeks.

Since this instrument is pretty limited in its use being a single line 
spectrometer, I connected its raw pulse output to a USB sound card and 
recorded the pulses with a sample rate of 96000/s. Since I do not like 
software I did not write myself, I then wrote a simple Perl program to 
process the data gathered like this which can be found in the subdirectory
[w2s](soundcard_perl).

During Christmas 2020/2021 I started building a more hardware centric 
solution which is described in the folder 
[tiny_spectrometer](tiny_spectrometer).
