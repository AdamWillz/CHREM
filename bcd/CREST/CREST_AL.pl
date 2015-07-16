#!/usr/bin/perl

# ====================================================================
# CREST_AL.pl
# Author: Adam Wills
# Date: Jul 2015
# Copyright: Carleton University

# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name]

# DESCRIPTION:
# This script adds roof mounted PV modules to an existing set of houses generated by the CHREM



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

use threads;	# threads-1.89 (to multithread the program)
use Data::Dumper;	# to dump info to the terminal for debugging purposes
use File::Copy;
use Storable  qw(dclone);
use POSIX qw(ceil floor);
use XML::Simple; # to parse the XML results files
use XML::Dumper;

use lib qw(../../scripts/modules);
use General;
use Cross_reference;
use AL_Profile_Gen;

# --------------------------------------------------------------------
# Declare the global variables
# --------------------------------------------------------------------

my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name;   # Read in city name from command line

# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Hse_Gen_(.+)_Issues.txt/$1/, <../../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------

if (@ARGV < 3) {die "Three arguments are required: house_types regions set_name\n";};	# check for proper argument count

# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift (@ARGV), shift (@ARGV), shift (@ARGV));
# Verify the provided set_name
#if (defined($possible_set_names->{$set_name})) { # Check to see if it is defined in the list
	$set_name =  '_' . $set_name; # Add and underscore to the start to support subsequent code
#}
#else { # An inappropriate set_name was provided so die and leave a message
#	die "Set_name \"$set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
#};
# --------------------------------------------------------------------
# Load in CHREM NN data
# --------------------------------------------------------------------
my $NNinPath = '../../NN/NN_model/ALC-Inputs-V2.csv';
my $NNinput = &cross_ref_readin($NNinPath);
my $NNresPath = '../../NN/NN_model/ALC-Results.csv';
my $NNoutput = &cross_ref_readin($NNresPath);

# --------------------------------------------------------------------
# Load in CREST Databases
# --------------------------------------------------------------------
my $OccSTART = 'occ_start_states.xml';
my $occ_strt = XMLin($OccSTART);

my $LIGHT = 'lightsim_inputs.xml';
my $light_calib = XMLin($LIGHT);

# -----------------------------------------------
# Read in the CWEC weather data crosslisting
# -----------------------------------------------
my $climate_ref = &cross_ref_readin('../../climate/Weather_HOT2XP_to_CWEC.csv');	# create an climate reference crosslisting hash

# --------------------------------------------------------------------
# Begin multi-threading for regions and house types
# --------------------------------------------------------------------
MULTI_THREAD: {
	print "Multi-threading for each House Type and Region : please be patient\n";
	
	my $thread;	# Declare threads for each type and region
	my $thread_return;	# Declare a return array for collation of returning thread data
	
	foreach my $hse_type (values (%{$hse_types})) {	# Multithread for each house type
		foreach my $region (values (%{$regions})) {	# Multithread for each region
			# Add the particular hse_type and region to the pass hash ref
			my $pass = {'hse_type' => $hse_type, 'region' => $region, 'setname' => $set_name};
			$thread->{$hse_type}->{$region} = threads->new(\&main, $pass);	# Spawn the threads and send to main subroutine
		};
	};
    
    foreach my $hse_type (&array_order(values %{$hse_types})) {	# return for each house type
		foreach my $region (&array_order(values %{$regions})) {	# return for each region type
			$thread_return->{$hse_type}->{$region} = $thread->{$hse_type}->{$region}->join();	# Return the threads together for info collation
          
        };
    };
};


# --------------------------------------------------------------------
# Main code that each thread evaluates
# --------------------------------------------------------------------

MAIN: {
	sub main () {
		my $pass = shift;	# the hash reference that contains all of the information

		my $hse_type = $pass->{'hse_type'};	# house type number for the thread
		my $region = $pass->{'region'};	# region number for the thread
        my $set_name = $pass->{'setname'};	# region number for the thread
        my $return; # HASH to store issues
        my $issue = 0; # Issue counter

        push (my @dirs, <../../$hse_type$set_name/$region/*>);	#read all hse directories and store them in the array
        #print Dumper @dirs;

        # --------------------------------------------------------------------
        # Begin processing each house model
        # --------------------------------------------------------------------
        RECORD: foreach my $dir (@dirs) {
            my $hse_name = $dir;
            $hse_name =~ s{.*/}{};
            my $hse_occ; # Number of occupants in dwelling
            my @Occ; # Array to hold occupancy 
            my $CSDDRD; # declare a hash reference to store the CSDDRD data. This will only store one house at a time and the header data
            
            # --------------------------------------------------------------------
            # Find NN data
            # --------------------------------------------------------------------
            my $NNdata;
            my $bFound = 0;
            NN_IN: foreach my $data (keys (%{$NNinput->{'data'}})) {
                if ($data  =~ /^$hse_name/) {
                    $NNdata = $NNinput->{'data'}->{$data};
                    $bFound = 1;
                    last NN_IN;
                }
            };
            if (!$bFound) {
                $issue++;
                $return->{$hse_name}->{"$issue"} = "Error: Couldn't find NN record";
                next RECORD;
            };

            my $NNo;
            $bFound = 0;
            NN_OUT: foreach my $data (keys (%{$NNoutput->{'data'}})) {
                if ($data  =~ /^$hse_name/) {
                    $NNo = $NNoutput->{'data'}->{$data};
                    $bFound = 1;
                    last NN_OUT;
                }
            };
            if (!$bFound) {# TODO: ERROR HANDLING
                $issue++;
                $return->{$hse_name}->{"$issue"} = "Error: Couldn't find NN output";
                next RECORD;
            };
            
            # --------------------------------------------------------------------
            # Find CSDDRD data
            # --------------------------------------------------------------------
            my $file = '../../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_type . '_subset_' . $region;
            my $ext = '.csv';
            my $CSDDRD_FILE;
            my $bCSDDRD = 0;
            open ($CSDDRD_FILE, '<', $file . $ext) or die ("Can't open datafile: $file$ext");	# open readable file
            CSDDRD: while ($CSDDRD = &one_data_line($CSDDRD_FILE, $CSDDRD)) {
                if ($CSDDRD->{'file_name'} =~ /^$hse_name/) {
                    $bCSDDRD = 1;
                    last CSDDRD;
                };
            }; # END CSDDRD
            if (!$bCSDDRD) { # Could not find record
                $issue++;
                $return->{$hse_name}->{"$issue"} = "Error: Couldn't find CSDDRD data";
                next RECORD;
            };
            close $CSDDRD_FILE;
            
            # Determine the climate for this house from the Climate Cross Reference
			my $climate = $climate_ref->{'data'}->{$CSDDRD->{'HOT2XP_CITY'}};	# shorten the name for use this house

            # --------------------------------------------------------------------
            # Generate the occupancy profiles
            # --------------------------------------------------------------------
            $hse_occ = $NNdata->{'Num_of_Children'}+$NNdata->{'Num_of_Adults'};
            my $IniState = &setStartState($hse_occ,$occ_strt->{'wd'}->{"$hse_occ"}); # TODO: Determine 'we' or 'wd'
            my $Occ_ref = &OccupancySimulation($hse_occ,$IniState,4); # TODO: Determine day of the week
            @Occ = @$Occ_ref;
            
            # --------------------------------------------------------------------
            # Generate Lighting Profile
            # --------------------------------------------------------------------
            # --- Irradiance data
            my $loc = $climate->{'CWEC_FILE'};  # Determine climate for this dwelling
            $loc =~ s{\.[^.]+$}{}; # Remove extension
            $loc = $loc . '.out'; # Name of irradiance file
            my $irradiance = "Global_Horiz/$loc";
            my $Irr_ref = &GetIrradiance($irradiance); # Load the irradiance data
            my @Irr = @$Irr_ref;

            # --- Bulb data
            my @fBulbs = (); # Array to hold wattage of each bulb in the dwelling
            my $iBulbs=0; # Number of bulbs/lamps for dwelling 
            my @BulbType = qw(Fluorescent Halogen Incandescent);
            foreach my $bulb (@BulbType) { # Read number of bulbs from CHREM NN inputs
                $iBulbs = $iBulbs + $NNdata->{$bulb};
            };
            
            
            # --- Call Lighting Simulation
            my $fCalibrationScalar = $light_calib->{$region}->{$hse_type}->{'Calibration'};
            my $MeanThresh = $light_calib->{'threshold'}->{'mean'};
            my $STDThresh = $light_calib->{'threshold'}->{'std'};
            my ($light_ref,$AnnPow) = &LightingSimulation(\@Occ,\@Irr,\@fBulbs,$fCalibrationScalar,$MeanThresh,$STDThresh);

        }; # END RECORD
        
    print "Thread for Timestep reports mode of $hse_type $region - Complete\n";
    
    return ($return);
    
    };  # END sub main
};	# END MAIN

# -----------------------------------------------
# Subroutines
# -----------------------------------------------
#SUBROUTINES: {
#
#    sub clean_up_dir {
#        my $set_name = shift;
#        my $file = shift;
#    
#        # Find all the "orig" files for the model and reinstate them
#        my @files = glob "$file/*.orig";
#        for (0..$#files){
#            my $To_Del = $files[$_];
#            $To_Del =~ s/\.orig$//; # Name of new file to be removed
#            unlink $To_Del;
#            rename $files[$_],$To_Del;
#        };
#    
#    	return (1);
#	};
#
#};
