# A simple Perl program to generate Gamma spectrograms

The easiest way to build something at least resembling a Gamma spectrometer
is to record the peaks from a photomultiplier tube with its associated 
scintillator crystal by a sound card and then process the resulting data.

I used [Audacity](https://www.audacity.de) to record the data from my 
photomultiplier. I used a cheap USB soundcard U-CONTROL UCA202 set to
96000 samples per second. The resulting audio file must be saved as a WAV-file
for further processing.

This post processing is done with the following simple Perl program:
```
# Usage: perl w2s.pl [-n] <filename>
#   - The program expects positive peaks in the raw data. If negative peaks are 
#     to be processed, the -n flag must be specified.
#   - The peaks are written into an output file which has 32768 entries, each
#     corresponding to a single energy.
#   - The result is automatically displayed using a local gnuplot installation.
#
# Bernd Ulmann, 30.12.2020
# 03.01.2020    Bernd Ulmann    Added $min_diff to get rid of the many 
#                               artifacts looking like low energy peaks.

use strict;
use warnings;
use Audio::Wav;
use Getopt::Std;

my $bucket_size = 1;    # Leave it at 1 - definitely! ;-)
my $min_diff = 5;       # Minimum difference in height for detecting an
                        # increase/decrease in slope
my $threshold = 10;

my %options;
getopts('n', \%options);

die "Usage: $0 <filename>\n" unless @ARGV == 1;
my ($filename) = @ARGV;
my ($destination) = $filename =~ /(^.+)\./;

print "Reading audio file...\n";
my $data = Audio::Wav->read($filename);
my $sampling_rate = $data->details()->{sample_rate};
my $samples = $data->details()->{data_length} / 2;
my $raw = $data->read_raw_samples($samples);
$destination .= "_B${bucket_size}_SR${sampling_rate}.peaks";

print "Preprocessing raw data...\n";
my @values;
for my $value (unpack('v*', $raw)) {
    $value = -(65536 - $value) if $value > 32767;
    $value = -$value if $options{n};
    $value = 0 if $value < $threshold;
    push(@values, $value);
}
$raw = undef; # That looks silly but saves some memory speeding things up a bit

print 'Detecting peaks (', scalar(@values), " values)...\n";
my @peaks;
my ($down, $last) = (0, pop(@values));
for my $value (@values) {
    unless ($down) {
        if ($value < $last - $min_diff) {
            my $index = int($last / $bucket_size);
            $peaks[$index]++;
            $down = 1;
        }
        $last = $value;
    } else {
        $down = 0 if $value > $last + $min_diff;
        $last = $value;
    }
}

print "Writing results...\n";
open(my $handle, '>', $destination) or die "Could not open $destination: $!\n";
print $handle defined($peaks[$_]) ? $peaks[$_] : 0, "\n" for 0 .. (32767 / $bucket_size) + 1;
#print $handle "$_\n" for @values;
close($handle);

system(qq(gnuplot -e "plot '$destination' w l" -));
```

