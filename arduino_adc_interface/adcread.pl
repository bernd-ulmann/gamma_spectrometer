#
#  This simple Perl program either reads raw data from the Arduino based ADC
# adapter which works with Nuclear Data ADCs such as the ND580 or with 
# similar Canberra devices like the Canberra 1510.
#
#  This program can perform a number of actions as described in the help 
# message below.
#
#  Data is displayed using gnuplot. The plot is not normalized with respect to
# its x- and y-axes, so that energy calibration must be done using the -e 
# parameter. 
#
# 2022-04-09    B. Ulmann   Initial version based on the old Perl program 
#                           targeted at the homebrew simple Gamma spectrometer.
# 2022-04-13    B. Ulmann   Added keV-scaling.
# 2023-03-19    B. Ulmann   Added JPG output
# 2026-07-25    B. Ulmann   Added denser xtics and log scale
#

use strict;
use warnings;
use File::Temp;
use Getopt::Long qw(GetOptions);
use Device::SerialPort;
use Time::HiRes qw(usleep);
use POSIX qw(strftime);

my $baudrate = 115200;
my $channels = 2048;

die "Usage: perl $0 {-u <usb_port> | -f <filename>} 
                    [-w <window_size>] 
                    [-f <filename>] Reads data from a file
                    [-e <energy of last channel]
                    [-d <destination_filename>] Timestamp by default
                    [-t <title>]
                    [-l] set y axis to log scale
                    [-p] generate a plot
                    [-j] do not plot but create a jpg picture
                    [-a] alpha spectrum (different parameters)
                    [-y <value>] set y-range
       perl $0 -r (to reset the device)
       perl $0 -s (to get statistics)\n" 
    unless @ARGV;

my ($usb_port, $window_size, $filename, $destination, $statistics, $reset, 
    $title, $jpg, $plot, $yrange, $alpha, $logscale, $energy);
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
           'l'   => \$logscale,
           'e=s' => \$energy,
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

        my ($increment, $x_label, $x_range);
        if (!defined($energy)) {
            $x_label = 'Channel #';
            $increment = 1;
            $x_range = $channels;
        } else {
            $increment = $energy / $channels;
            $x_label = 'Energy [keV]';
            $x_range = $energy;
        }

        $handle = File::Temp->new();
        my $tempfile = $handle->filename();
        my $x = 0;
        print $handle $x += $increment, " $_\n" for @smoothed;
        close($handle);

        my $command;
        my $y = $yrange   ? "set yrange [0:$yrange]; " : '';
        my $l = $logscale ? 'set logscale y 10; '      : '';
        
        # If the gnuplot command ends with '-' gnuplot will not be terminated 
        # after generating the plot.

        if ($jpg) {
            $command = qq(gnuplot -e "set terminal jpeg; set output '$date.jpg'; $y set xrange [0:$x_range]; set title '$title'; set xlabel '$x_label'; set ylabel 'Counts'; set xtics 0, 100; set xtics rotate by 90; $l plot '$tempfile' notitle w l");
        } else {
            $command = qq(gnuplot -e "$y set xrange [0:$x_range]; set title '$title'; set xlabel '$x_label'; set ylabel 'Counts'; set xtics 0, 100; set xtics rotate by 90; $l plot '$tempfile' notitle w l");
        }
        system($command);
    }
}
