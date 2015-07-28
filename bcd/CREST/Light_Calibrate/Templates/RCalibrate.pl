#!/usr/bin/perl

# --------------------------------------------------------------------
# Declare modules which are used
# --------------------------------------------------------------------

use warnings;
use strict;

use Cwd;
use Data::Dumper;	# to dump info to the terminal for debugging purposes
use File::Copy;

# --------------------------------------------------------------------
# Global variables
# --------------------------------------------------------------------
my $CMDfile;        # Input command file
my $CaliPath = "C:/cygwin/home/Adam/New_CHREM/bcd/CREST";

# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------
$CMDfile = shift(@ARGV);
open(my $CMD, '<', $CMDfile) or die ("Can't open datafile: $CMDfile");	# open readable file
my $DataStr = <$CMD>;
chomp $DataStr;
close $CMD;

# Parse out the input items
my @items = split / /, $DataStr;

my $hse_type = $items[0];
my $region = $items[1];
my $Target = $items[2];
my $fCalibrationScalar = $items[3];

# Get the current directory
my $CurDir = getcwd;

# Navigate to calibration script
chdir($CaliPath);

# Call the simulation
system ("perl Light_Calibrate.pl $hse_type $region $Target $fCalibrationScalar");

# Copy the output
copy("$fCalibrationScalar.out","$CurDir/Output.out") or die "Copy failed: $!";
unlink "$fCalibrationScalar.out";
# Copy the log
copy("$fCalibrationScalar.log","$CurDir/Output.log") or die "Copy failed: $!";
unlink "$fCalibrationScalar.log";

# return to original folder and exit
chdir($CurDir);