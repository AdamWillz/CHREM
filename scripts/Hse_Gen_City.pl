#!/usr/bin/perl

# ====================================================================
# Hse_Gen.pl
# Author: Lukas Swan
# Date: Oct 2009
# Copyright: Dalhousie University

# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name] [simulation timestep in minutes] [upgarde mode]

# DESCRIPTION:
# This script generates the esp-r house files for each house of the CSDDRD.
# It uses a multithreading approach based on the house type (SD or DR) and 
# region (AT, QC, OT, PR, BC). Which types and regions are generated is 
# specified at the beginning of the script to allow for partial generation.

# The script builds a directory structure for the houses which begins with 
# the house type as top level directories, regions as second level directories 
# and the house name (10 digit w/o ".HDF") inclusing the set_name for each house directory. It places 
# all house files within that directory (all house files in the same directory). 

# The script reads a set of input files:
# 1) CSDDRD type and region database (csv)
# 2) esp-r file templates (template.xxx)
# 3) weather station cross reference list

# The script copies the template files for each house of the CSDDRD and replaces
# and inserts within the templates based on the values of the CSDDRD house. Each 
# template file is explicitly dealt with in the main code (actually a sub) and 
# utilizes insert and replace subroutines to administer the specific house 
# information.

# The script is easily extendable to addtional CSDDRD files and template files.
# Care must be taken that the appropriate lines of the template file are defined 
# and that any required changes in other template files are completed.

# ===================================================================

# --------------------------------------------------------------------
# Declare modules which are used
# --------------------------------------------------------------------

use warnings;
use strict;

use CSV;	# CSV-2 (for CSV split and join, this works best)

# --------------------------------------------------------------------
# Declare the global variables
# --------------------------------------------------------------------

my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $Acro;       # String to hold house type (SD or DR)
my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name;   # Read in city name from command line
my $time_step;	# declare a scalar to hold the timestep in minutes
my $City;       # String to store city name
my $Glz;        # String to store glazing type (TMC or CFC)

# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------

if (@ARGV == 0 || @ARGV == 3) {die "Four arguments are required: house_types regions set_name simulation_time-step_(minutes); or \"db\" for database generation\n";};	# check for proper argument count
$hse_types = shift (@ARGV);
$regions = shift (@ARGV);
$set_name = shift (@ARGV);

if (shift (@ARGV) =~ /^([1-6]?[0-9])$/) {$time_step = $1;}
else {die "Simulation time-step must be equal to or between 1 and 60 minutes\n";};

if ($hse_types == 1) {
    $Acro = "SD_";
    }
elsif ($hse_types == 2){
    $Acro = "DR_";
    } else {
    die "Invalid house type. Must be 1 or 2\n";
}


print "Type: $hse_types     \n";   
print "Region: $regions     \n";    
print "Set Name: $set_name  \n";    
print "timestep:$time_step  \n";

my @Cities = split(/_/,$set_name);
$City = $Cities[0];
$Glz = $Cities[1];
print "City:$City  \n";
print "Window type:$Glz  \n";

my $CityFile = "../CityFiles/" . $Acro . $City . ".csv";


open( my $fh, '<', $CityFile) or die "Can't read file '$CityFile' [$!]\n";
while (my $line = <$fh>) {
    # Read and process house number from file
    chomp $line;
    $line =~ s{\.[^.]+$}{};
    # Prepare argument to pass to Hse_Gen_sara_TOT script
    my $SetGo = "Hse_Gen_sara_TOT.pl " . "$hse_types " . "$regions TEMP_" . "$Glz " . "$time_step 0 $line";
    system("/usr/bin/perl $SetGo ");
}



