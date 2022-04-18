#
#  This simple Perl program either reads raw data from the Arduino based ADC
# adapter which works with Nuclear Data ADCs such as the ND580 or with 
# similar Canberra devices like the Canberra 1510.
#
#  This program can perform several actions:
#
#   -r                              Reset the ACD adapter
#   -s                              Get statistics (events/maximum count)
#   -u <usb port> | -f <file name>  Read data from the device (USB) or a file
#       [-w <window size>]          Perform simple smoothing with a sliding window
#       [-d <file name>]            Save data to a file
#       [-t <title>]                Optional title for the plot
#
#  Data is displayed using gnuplot. The plot is not normalized with respect to
# its x- and y-axes, so there some other means of energy calibration must be 
# applied!
#
#  The program finished on the gnuplot prompt so the graph can be interactively
# rescaled, exported to various file formats etc. using the standard gnuplot
# capabilities.
#
# 2022-04-09    B. Ulmann   Initial version based on the old Perl program 
#                           targeted at the homebrew simple Gamma spectrometer.
# 2022-04-13    B. Ulmann   Added keV-scaling.
#

use strict;
use warnings;
use File::Temp;
use Getopt::Long qw(GetOptions);
use Device::SerialPort;
use Time::HiRes qw(usleep);

my $baudrate = 115200;
my $last_channel = 810;     # Energy of the last channel (experimentally determined).
                            # This is for the small PMT at 1.5 kV, with the 490B
                            # amplifier set to a gain of 5 * 4.

die "Usage: perl $0 [-w <window_size>] 
                       {-u <usb_port> | -f <filename>} 
                       [-d <destination_filename>]
                       [-t <title>]
       perl $0 -r (to reset the device)
       perl $0 -s (to get statistics)\n" 
    unless @ARGV;

my ($usb_port, $window_size, $filename, $destination, $statistics, $reset, $title);
$title = '';
GetOptions('u=s' => \$usb_port, 
           'w=s' => \$window_size, 
           'f=s' => \$filename, 
           'd=s' => \$destination, 
           's' =>   \$statistics, 
           'r' =>   \$reset,
           't=s' => \$title);

die "Either -f or -u must be specified!\n" if !defined($filename) and !defined($usb_port);
die "-f and -u are mutually exclusive!\n"  if  defined($filename) and  defined($usb_port);

my $port;
if (defined($usb_port)) {
    $port = Device::SerialPort->new($usb_port) or die "Unable to open USB-port: $!\n";
    $port->baudrate($baudrate);
    $port->databits(8);
    $port->parity('none');
    $port->stopbits(1);
}

if ($reset) {
    die "Reset requires a USB port to be specified!\n" unless defined($port);
    $port->write('x');  # Send reset command
    sleep(1);
    my $response = $port->lookfor();
    die "Illegal response from device: >>$response<<\n" unless $response =~ ".*Reset";
    print "Device has been reset.\n";
} elsif ($statistics) {
    die "Statistics requires a USB port to be specified!\n" unless defined($port);
    $port->write('c');  # Send reset command
    sleep(1);
    my $response = $port->lookfor();
    print "$response\n";
} else {
    my @data;
    if (defined($filename)) {
        open (my $handle, '<', $filename) or die "Could not open $filename: $!\n";
        while (my $record = <$handle>) {
            push(@data, $record) if $record =~ /^\d+$/;
        }
        close($handle);
    } else {
        print "Read data...\n";
        $port->write('r');  # Issue 'read' command to gamma spectrometer
        sleep(1);

        my $state = 0;
        for my $i (0 .. 3000) {
            usleep(100);
            my $response = $port->lookfor();
            last       if $response =~ /-+/ and $state == 1; # End of data area found
            $state = 1 if $response =~ /-+/ and $state == 0; # Start of data area found

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

    my (@smoothed, $counts);
    if (defined($window_size)) {
        print "Smoothing with window size $window_size.\n";
        my @window;
        push(@window, shift(@data)) for (1 .. $window_size);
        $counts += $_ for @window;
        for my $i (0 .. @data - 1) {
            my $average;
            $average += $_ for @window;
            push(@smoothed, $average / $window_size);
            shift(@window);
            $counts += $data[$i];
            push(@window, $data[$i]);
        }
    } else {
        @smoothed = @data;
        $counts += $_ for @data;
        print "No smoothing applied.\n";
    }
    print "$counts events detected.\n";

    my $handle = File::Temp->new();
    my $tempfile = $handle->filename();
    my $x = 0;
    my $increment = $last_channel / 2048;
    print $handle $x += $increment, " $_\n" for @smoothed;
    close($handle);

    system(qq(gnuplot -e "set xrange [0:$last_channel]; set title '$title'; set xlabel 'Energy [keV]'; set ylabel 'counts'; plot '$tempfile' w l" -));
}
