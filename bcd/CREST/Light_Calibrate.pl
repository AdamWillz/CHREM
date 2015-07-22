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
my $calibration='LightCalibrate.xml';   # Calibration data input
my $Results;    # HASH to hold calibration results

# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------

if (@ARGV < 2) {die "Three arguments are required: house_types regions\n";};	# check for proper argument count

# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
($hse_types, $regions) = &hse_types_and_regions_and_set_name(shift (@ARGV), shift (@ARGV));


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
my $light_sim = XMLin($LIGHT);

# --------------------------------------------------------------------
# Load in calibration data
# --------------------------------------------------------------------
my $LCalib = XMLin($calibration);

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
			my $pass = {'hse_type' => $hse_type, 'region' => $region};
			$thread->{$hse_type}->{$region} = threads->new(\&main, $pass);	# Spawn the threads and send to main subroutine
		};
	};
    
    foreach my $hse_type (&array_order(values %{$hse_types})) {	# return for each house type
		foreach my $region (&array_order(values %{$regions})) {	# return for each region type
			$thread_return->{$hse_type}->{$region} = $thread->{$hse_type}->{$region}->join();	# Return the threads together for info collation
          
        };
    };
    
    # Print out Error report
    my $ErrorFile = 'Calibration_Errors.csv';
    open (my $failure, '>', $ErrorFile) or die ("Can't create $ErrorFile");
    print $failure "hse_type,region,hse,error\n";
    foreach my $hse_type (&array_order(values %{$hse_types})) {	# return for each house type
		foreach my $region (&array_order(values %{$regions})) {	# return for each region type
            foreach my $houses (keys (%{$thread_return->{$hse_type}->{$region}})) {	# Each house
                if ($houses !~ m/Calibration_Scalar/) { # Then it's an error
                      foreach my $iss (keys (%{$thread_return->{$hse_type}->{$region}->{$houses}})) {	# Each issue
                            my $msg = $thread_return->{$hse_type}->{$region}->{$houses}->{"$iss"};
                            print $failure "$hse_type,$region,$houses,$msg\n";
                      };
                };
            };
        };
    };
    close $failure;
    
    # Print out calibration scalars report
    my $ScalarFile = 'Calibration_Scalars.csv';
    open (my $CScakars, '>', $ScalarFile) or die ("Can't create $ScalarFile");
    print $failure "hse_type,region,Calibration Scalar,True Absolute Error,Predicted Consumption, Message\n";
    foreach my $hse_type (&array_order(values %{$hse_types})) {	# return for each house type
		foreach my $region (&array_order(values %{$regions})) {	# return for each region type
            foreach my $calib (keys (%{$thread_return->{$hse_type}->{$region}})) {	# Each house
                if ($calib =~ m/Calibration_Scalar/) { # Then it's the calibration scalar
                    my $sc = $thread_return->{$hse_type}->{$region}->{$calib}->{'Value'};
                    my $TE = $thread_return->{$hse_type}->{$region}->{$calib}->{'Error'};
                    my $pred = $thread_return->{$hse_type}->{$region}->{$calib}->{'Predicted'};
                    my $msgs = $thread_return->{$hse_type}->{$region}->{$calib}->{'Msg'};
                    print $failure "$hse_type,$region,$sc,$TE,$pred,$msgs\n";
                };
            };
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
        my $return; # HASH to store issues
        my $issue = 0; # Issue counter
        my @BTypes=(); # Array to hold all bulb categories
        foreach my $blb (keys (%{$light_sim->{'Types'}})) { # Read an store all bulb categories
            push(@BTypes,$blb);
        };

        # Declare the specific CSDDRD file for this set
        my $record = '../../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_type . '_subset_' . $region;
        my $exten = '.csv';
        my $LIST; # CSDDRD file handle
        my $CSDDRD; # declare a hash reference to store the CSDDRD data. This will only store one house at a time and the header data

        # --------------------------------------------------------------------
        # Get the calibration data for this hse_type and region
        # --------------------------------------------------------------------
        my $Target = $LCalib->{$region}->{$hse_type}->{'Target'};
        my $iniDelta = $LCalib->{$region}->{$hse_type}->{'Initial_Guess'} + (($LCalib->{$region}->{$hse_type}->{'Initial_Guess'})*($LCalib->{'Perturb'}));
        my @Xs = ($LCalib->{$region}->{$hse_type}->{'Initial_Guess'},$iniDelta);
        my @FcnOuts = ();
        my $TrueError;  # Relative value for true error [%]
        
        # --------------------------------------------------------------------
        # Determine the calibration scalar using the modified Secant Method
        # --------------------------------------------------------------------
        my $y=0;
        SECANT: while ($y < $LCalib->{'Max_iter'}) {
            ITERATION: for (my $b=0;$b<=1;$b++) { # Determine output for value and value plus delta
                my @AggAnnual=(); # Aggregated annual consumptions
                # --------------------------------------------------------------------
                # Begin processing each house model for the region and house type
                # --------------------------------------------------------------------
                open ($LIST, '<', $record . $exten) or die ("Can't open datafile: $record$exten");	# open readable file
                RECORD: while ($CSDDRD = &one_data_line($LIST, $CSDDRD)) { # Each house in the CSDDRD record
                    my $hse_name = $CSDDRD->{'file_name'};
                    $hse_name =~ s{\.[^.]+$}{}; # Remove any extensions
                    my $hse_occ; # Number of occupants in dwelling
                    my @Occ; # Array to hold occupancy 
                    
                    # --------------------------------------------------------------------
                    # Find NN data
                    # --------------------------------------------------------------------
                    my $NNdata;
                    if (exists $NNinput->{'data'}->{"$hse_name.HDF"}) {
                        $NNdata = $NNinput->{'data'}->{"$hse_name.HDF"};
                    } elsif (exists $NNinput->{'data'}->{"$hse_name.HDF.No-Dryer"}) {
                        $NNdata = $NNinput->{'data'}->{"$hse_name.HDF.No-Dryer"};
                    } else {
                        $issue++;
                        $return->{$hse_name}->{"$issue"} = "Error: Couldn't find NN record";
                        next RECORD;
                    };
        
                    my $NNo;
                    if (exists $NNoutput->{'data'}->{"$hse_name.HDF"}) {
                        $NNo = $NNoutput->{'data'}->{"$hse_name.HDF"};
                    } elsif (exists $NNoutput->{'data'}->{"$hse_name.HDF.No-Dryer"}) {
                        $NNo = $NNoutput->{'data'}->{"$hse_name.HDF.No-Dryer"};
                    } else {
                        $issue++;
                        $return->{$hse_name}->{"$issue"} = "Error: Couldn't find NN output";
                        next RECORD;
                    };
                    
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
                    foreach my $bulb (@BulbType) { # Read number of bulbs in dwelling from CHREM NN inputs
                        $iBulbs = $iBulbs + $NNdata->{$bulb};
                    };
                    # Assign wattage for each bulb
                    for (my $i=1;$i<=$iBulbs;$i++) { # Each bulb
                        my $r1 = rand();
                        my $cml=0;
                        my $category;
                        Category: foreach my $blb (@BTypes) { # Loop through each bulb category
                            $cml=$cml+$light_sim->{'Types'}->{$blb}->{'Share'};
                            if ($r1<=$cml) {
                                $category=$blb;
                                last Category;
                            };
                        }; # END Category
        
                        # Reset variables
                        $r1 = rand();
                        $cml=0;
                        my $BulbSubC;
                        BulbSub: foreach my $blb (keys (%{$light_sim->{'Types'}->{$category}->{'sub'}})) { # Loop through each bulb sub-category
                            $cml=$cml+$light_sim->{'Types'}->{$category}->{'sub'}->{$blb}->{'Share'};
                            if ($r1<=$cml) {
                                $BulbSubC=$blb;
                                last BulbSub;
                            };
                        }; # END BulbSub
                        if (not defined($BulbSubC)) {
                            print "Category is $category\n";
                            print "Random Number is $r1\n";
                            print "Cumulative is $cml\n";
                            die "Please check the distribution data";
                        };
                        # Store wattage of this bulb
                        push(@fBulbs, $light_sim->{'Types'}->{$category}->{'sub'}->{$BulbSubC}->{'Wattage'});
                    };
        
                    # --- Call Lighting Simulation
                    my $MeanThresh = $LCalib->{'threshold'}->{'mean'};
                    my $STDThresh = $LCalib->{'threshold'}->{'std'};
                    my ($light_ref,$AnnPow) = &LightingSimulation(\@Occ,\@Irr,\@fBulbs,$Xs[$b],$MeanThresh,$STDThresh);
                    my @Light = @$light_ref;
                    push(@AggAnnual,$AnnPow);
        
                }; # END RECORD
                
                close $LIST;

                # --------------------------------------------------------------------
                # determine the average per household
                # --------------------------------------------------------------------
                my $Agg=0;
                my $Nhousehold = scalar @AggAnnual;
                foreach my $load (@AggAnnual) {
                    $Agg=$Agg+$load;
                };
                my $kWhAverage = $Agg/$Nhousehold;
                $FcnOuts[$b] = $Target-$kWhAverage;
            
            }; # END ITERATION
            my $datestring = localtime();
            print "$region $hse_type completed iteration $y: $datestring\n";
            
            # Determine the relative true error
            $TrueError = abs($FcnOuts[0]/$Target)*100;
            
            if ($TrueError <= $LCalib->{'Tol'}) { # Achieved convergence, exit
                last SECANT;
            };

            # Determine next guess
            my $NewGuess = $Xs[0] - (($LCalib->{'Perturb'}*$Xs[0]*$FcnOuts[0])/($FcnOuts[1]-$FcnOuts[0]));
            $Xs[0] = $NewGuess;
            $Xs[1] = $NewGuess+($NewGuess*$LCalib->{'Perturb'});

            $y++; # increment the iteration
        }; # END SECANT

        $return->{'Calibration_Scalar'}->{'Value'} = $Xs[0];
        $return->{'Calibration_Scalar'}->{'Error'} = $TrueError;
        $return->{'Calibration_Scalar'}->{'Predicted'} = $FcnOuts[0];
        
        if ($y == $LCalib->{'Max_iter'}) { # Did not converge
            $return->{'Calibration_Scalar'}->{'Msg'} = 'Did not converge';
        } else { # Did converge
            $return->{'Calibration_Scalar'}->{'Msg'} = 'Converged';
        };
    
    return ($return);
    
    };  # END sub main
};	# END MAIN
