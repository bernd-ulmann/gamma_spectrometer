# This program has been configured for an amplifier setting of a coarse gain 
# of 4 and a fine gain of 3!
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
# 2023-03-19    B. Ulmann   Added JPG output
#

use strict;
use warnings;
use File::Temp;
use Getopt::Long qw(GetOptions);
use Device::SerialPort;
use Time::HiRes qw(usleep);
use POSIX qw(strftime);

my $baudrate = 115200;
my $last_channel_gamma = 2000;  # Energy of the last channel (experimentally 
                                # determined). This is the default for my gamma
                                # spectroscopy setup (PMT at 1.5 kV, 490B 
                                # amplifier).
my $channels_gamma = 1900;
my $last_channel_alpha = 12000; # The same for my alpha spectrosopcy setup.
my $channels_alpha = 2048;

die "Usage: perl $0 [-w <window_size>] 
                       {-u <usb_port> | -f <filename>} 
                       [-d <destination_filename>]
                       [-t <title>]
                       [-p] generate a plot
                       [-j] do not plot but create a jpg picture
                       [-a] alpha spectrum (different parameters)
       perl $0 -r (to reset the device)
       perl $0 -s (to get statistics)\n" 
    unless @ARGV;

my ($usb_port, $window_size, $filename, $destination, $statistics, $reset, 
    $title, $jpg, $plot, $yrange, $alpha);
$title = '';
GetOptions('u=s' => \$usb_port, 
           'w=s' => \$window_size, 
           'f=s' => \$filename, 
           'd=s' => \$destination, 
           's'   => \$statistics, 
           'r'   => \$reset,
           'j'   => \$jpg,
           'p'   => \$plot,
           'a'   => \$alpha,
           'y=s' => \$yrange,
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

my $date = strftime("%Y%m%d-%H%M%S", localtime);
$title |= "$date";
$title = $filename if defined($filename);

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
            chomp($record);
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

    my $handle;
    unless (defined($filename)) {
        $destination //= "$date.dat";
        print "Saving raw data to $destination.\n";
        open($handle, '>', $destination) or die "Could not open $destination: $!\n";
        print $handle "$_\n" for @data;
        close($handle);
    }

    if ($plot or $jpg) {
        my ($counts, @smoothed);
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

        my $last_channel = $last_channel_gamma;
        $last_channel = $last_channel_alpha if $alpha;

        my $channels = $channels_gamma;
        $channels = $channels_alpha if $alpha;

        $handle = File::Temp->new();
        my $tempfile = $handle->filename();
        my $x = 0;
        my $increment = $last_channel / $channels;
        print $handle $x += $increment, " $_\n" for @smoothed;
        close($handle);

        # If the gnuplot command ends with '-' gnuplot will not be terminated 
        # after generating the plot.
        my $command;
        my $y = '';
        $y = "set yrange [0:$yrange]; " if ($yrange);

        if ($jpg) {
            $command = qq(gnuplot -e "set terminal jpeg; set output '$date.jpg'; $y set xrange [0:$last_channel]; set title '$title'; set xlabel 'Energy [keV]'; set ylabel 'Counts'; plot '$tempfile' notitle w l");
        } else {
            $command = qq(gnuplot -e "$y set xrange [0:$last_channel]; set title '$title'; set xlabel 'Energy [keV]'; set ylabel 'Counts'; plot '$tempfile' notitle w l");
        }
        system($command);
    }
}
