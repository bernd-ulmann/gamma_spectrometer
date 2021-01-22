#
#  This simple Perl program either reads raw data from the Arduino based tiny
# Gamma spectrometer or reads similar data from a flat file with one record
# per energy level. It can perform an optional smoothing of the data by 
# computing a moving average. The data is then displayed using gnuplot.
# The plot is not normalized regarding its x- and y-axes, so there some other
# means of energy calibration must be applied.
#
#  The program expects the following command line arguments:
#   -u <usb-port>       -u and -f are mutually exclusive - 
#   -f <filename>       either file or usb-port!
#   -w <window_size>    -w is optional and specifies the size
#                       moving average window. If omitted, no 
#                       smoothing is performed.
#   -d <filename>       -d specifies a destination file to
#                       which the raw data is written.
#
# 2021-01-21    B. Ulmann   Initial version
#

use strict;
use warnings;
use File::Temp;
use Getopt::Long qw(GetOptions);
use Device::SerialPort;
use Time::HiRes qw(usleep);

my $baudrate = 115200;

die "Usage: perl $0 [-w <window_size>] {-u <usb_port> | -f <filename>} [-d <destination_filename>]\n" 
    unless @ARGV;

my ($usb_port, $window_size, $filename, $destination);
GetOptions('u=s' => \$usb_port, 'w=s' => \$window_size, 'f=s' => \$filename, 'd=s' => \$destination);

die "Either -f or -u must be specified!\n" if !defined($filename) and !defined($usb_port);
die "-f and -u are mutually exclusive!\n"  if  defined($filename) and  defined($usb_port);

my @data;
if (defined($filename)) {
    open (my $handle, '<', $filename) or die "Could not open $filename: $!\n";
    while (my $record = <$handle>) {
        push(@data, $record) if $record =~ /^\d+$/;
    }
    close($handle);
} else {
    my $port = Device::SerialPort->new($usb_port) or die "Unable to open USB-port: $!\n";
    $port->baudrate($baudrate);
    $port->databits(8);
    $port->parity('none');
    $port->stopbits(1);

    $port->write('r');  # Issue 'count' command to gamma spectrometer
    my $state = 0;
    for (0 .. 2000) {
        usleep(1000);
        my $response = $port->lookfor();
        last       if $response =~ /------------$/ and $state == 1; # End of data area found
        $state = 1 if $response =~ /------------$/ and $state == 0; # Start of data area found

        push(@data, $response) if $response =~ /^\d+/;
    }
}
print scalar(@data), " records read.\n";

if (defined($destination)) {
    print "Saving raw data to $destination.\n";
    open(my $handle, '>', $destination) or die "Could not open $destination: $!\n";
    print $handle "$_\n" for @data;
    close($handle);
}

my @smoothed;
if (defined($window_size)) {
    print "Smoothing with window size $window_size.\n";
    my @window;
    push(@window, shift(@data)) for (1 .. $window_size);
    for my $i (0 .. @data - 1) {
        my $average;
        $average += $_ for @window;
        push(@smoothed, $average / $window_size);
        shift(@window);
        push(@window, $data[$i]);
    }
} else {
    @smoothed = @data;
    print "No smoothing applied.\n";
}

my $handle = File::Temp->new();
my $tempfile = $handle->filename();
print $handle "$_\n" for @smoothed;
close($handle);

system(qq(gnuplot -e "plot '$tempfile' w l" -));
