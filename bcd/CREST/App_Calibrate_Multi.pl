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

use Data::Dumper;	# to dump info to the terminal for debugging purposes
use File::Copy;
use Storable  qw(dclone);
use XML::Simple; # to parse the XML results files
use XML::Dumper;
use threads;
use threads::shared;
use POSIX qw(ceil floor);

use lib qw(../../scripts/modules);
use General;
use Cross_reference;
use AL_Profile_Gen;
use Upgrade;

# --------------------------------------------------------------------
# Declare the global variables
# --------------------------------------------------------------------

my $hse_type  :shared;
my $region    :shared;
my $Target    :shared;             # Target average annual appliance consumption for region and hse_type [kWh/yr/hsehld]
our $occ_strt;             # HASH holding the active occupants at first timestep pdf
our $CREST;             # HASH holding CREST input data
our $ColdApp;             # HASH to hold the cold appliance data
our $App;             # HASH holding general appliance data
our $Activity;             # HASH holding the activity statistics
my $phi = 1.61803398874989;  # Golden ratio
my $iThreads = 16;                  # Number of threads

# --------------------------------------------------------------------
# Declare the local variables
# --------------------------------------------------------------------

my $hse_types;	    # declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions;	    # declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $xlow;
my $xu;
my @hse_TOT;        # Array to hold the list of all houses for region and type
my @hse_list;        # Array to hold the subset of houses for this region and type
my $MAXTOL = 0.001; # Maximum error estimate [%]
my $MaxIter = 35;   # Maximum iterations
my $SubSet = 377;   # Number of houses to run each iteration

# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------

if (@ARGV < 5) {die "Four arguments are required: house_type region Target low high\n";};	# check for proper argument count

# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
($hse_types, $regions) = &hse_types_and_regions_and_set_name(shift(@ARGV), shift(@ARGV));
my $Num_Keys = 0;
foreach my $stuff (keys (%{$hse_types})) {
    $hse_type = $hse_types->{$stuff};
    $Num_Keys++;
};
if($Num_Keys>1) {die "This script can only handle one house type at a time"};
    
$Num_Keys = 0;
foreach my $stuff (keys (%{$regions})) {
    $region = $regions->{$stuff};
    $Num_Keys++;
};
if($Num_Keys>1) {die "This script can only handle one region at a time"};

$Target = shift (@ARGV);
if ($Target <=0) {die "Invalid energy consumption target $Target. Must be positive"};

$xlow = shift (@ARGV);
if ($xlow <=0) {die "Invalid lower calibration scalar $xlow. Must be positive"};

$xu = shift (@ARGV);
if ($xu <=0 || $xu < $xlow) {die "Invalid higher calibration scalar $xu. Must be positive and greater than $xlow"};

# --------------------------------------------------------------------
# Set the CREST input data
# --------------------------------------------------------------------
my $LogFile = "GoldenSection_" . $hse_type . "_" . "$region.log";
open(my $LogFH, '>', $LogFile) or die ("Can't open datafile: $LogFile");
SET_CREST: {

    # --------------------------------------------------------------------
    # Load in CHREM NN data
    # --------------------------------------------------------------------
    my $NNinPath = '../../NN/NN_model/ALC-Inputs-V2.csv';
    my $NNinput = &cross_ref_readin($NNinPath);

    # --------------------------------------------------------------------
    # Scan the CSDDRD
    # --------------------------------------------------------------------
    my $record = '../../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_type . '_subset_' . $region;
    my $exten = '.csv';
    my $CSDDRD; # declare a hash reference to store the CSDDRD data. This will only store one house at a time and the header data
    open (my $LIST, '<', $record . $exten) or die ("Can't open datafile: $record$exten");	# open readable file
    REC: while ($CSDDRD = &one_data_line($LIST, $CSDDRD)) { # Each house in the CSDDRD record
        my $hse_name = $CSDDRD->{'file_name'};
        my $hse_occ; # Number of occupants in dwelling
        
        # Get the name of the dwelling
        $hse_name =~ s{\.[^.]+$}{}; # Remove any extensions
        
        # --------------------------------------------------------------------
        # Find NN data
        # --------------------------------------------------------------------
        my $NNdata;
        if (exists $NNinput->{'data'}->{"$hse_name.HDF"}) {
            $NNdata = $NNinput->{'data'}->{"$hse_name.HDF"};
        } elsif (exists $NNinput->{'data'}->{"$hse_name.HDF.No-Dryer"}) {
            $NNdata = $NNinput->{'data'}->{"$hse_name.HDF.No-Dryer"};
        } else {
            #$issue++;
            #$return->{$hse_name}->{"$issue"} = "Error: Couldn't find NN record";
            #next RECORD;
            print $LogFH "Error: Couldn't find NN record for $hse_name\n";
            next REC;
        };
        # --------------------------------------------------------------------
        # Determine number of occupants
        # --------------------------------------------------------------------
        $hse_occ = $NNdata->{'Num_of_Children'}+$NNdata->{'Num_of_Adults'};
        if ($hse_occ>5) {   # WARN THE USER THE NUMBER OF OCCUPANTS EXCEEDS MODEL LIMITS
            # Set number of occupants to 5
            $hse_occ=5;
            print $LogFH "Warning: Occupants $hse_occ exceeded 5 for $hse_name\n";
        };
        
        # --------------------------------------------------------------------
        # Update the list and CREST inputs for the house
        # --------------------------------------------------------------------
        push(@hse_TOT,$hse_name);
        $CREST->{$hse_name}->{'Num_Occ'} = $hse_occ;
        $CREST->{$hse_name}->{'data'}= dclone $NNdata; # All the NN data associtated with this record
        $CREST->{$hse_name}->{'stove_fuel'}=$CSDDRD->{'stove_fuel_use'}; # Fuel use: 1 = NG or propane, 2 = electricity
        $CREST->{$hse_name}->{'dryer_fuel'}=$CSDDRD->{'dryer_fuel_used'}; # Fuel use: 1 = NG or propane, 2 = electricity
    }; # END REC
    close $LIST;
}; # END CSDDRD_READ
close $LogFH;

my($new_ref,$dummy)=&random_hse_shuffle(\@hse_TOT,$SubSet);
@hse_list = @$new_ref;

# --------------------------------------------------------------------
# Load in CREST Databases
# --------------------------------------------------------------------
print "Reading in the occupant start state XML - ";
my $OccSTART = 'Occ_Lighting/occ_start_states.xml';
$occ_strt = XMLin($OccSTART);
print "Complete\n";

# --------------------------------------------------------------------
# Load in cold appliance data
# --------------------------------------------------------------------
my $ColdFile = 'Appliance/Cold/Refrigerator_dist.xml';
$ColdApp->{'Refrigerator'}->{'dist'}=XMLin($ColdFile);
$ColdFile = 'Appliance/Cold/Refrigerator_eff.xml';
$ColdApp->{'Refrigerator'}->{'eff'}=XMLin($ColdFile);

$ColdFile = 'Appliance/Cold/Freezer_dist.xml';
$ColdApp->{'Freezer'}->{'dist'}=XMLin($ColdFile);
$ColdFile = 'Appliance/Cold/Freezer_eff.xml';
$ColdApp->{'Freezer'}->{'eff'}=XMLin($ColdFile);

# --------------------------------------------------------------------
# Load in general appliance data
# --------------------------------------------------------------------
my $AppFiles =  'Appliance/Appliance_inputs.xml';
$App = XMLin($AppFiles);

# -----------------------------------------------
# Load in the activity statistics
# -----------------------------------------------
print 'Loading the activity statistics';
my $ActStatpth = 'Appliance/activity_stats.csv';
$Activity = &ActiveStatParser($ActStatpth);
print " - Complete\n";

# --------------------------------------------------------------------
# Use Golden-Section Search to determine the minimum (Function is never negative)
# --------------------------------------------------------------------
my $datestring = localtime();
print "Starting the search at $datestring\n";
GOLDEN: {
    my $f1;
    my $f2;
    my $pred1;
    my $pred2;
    # Generate interior points
    my $d = 0.61803*($xu-$xlow);
    my $x1 = $xlow + $d;
    my $x2 = $xu - $d;
    
    # Threading variables
    if ($iThreads<=0) {die "Number of threads cannot be less than 1\n"};
    my $iChunk = floor(($#hse_list+1)/$iThreads); # Number of houses sent to each thread
    my $thread;
    my $AggkWh = 0; # Holds the aggregate average across the threads
    
    # Evaluate the interior points
    # $x1-----------------------------------------------------
    for(my $w=1; $w<=$iThreads; $w++){ # Multithread low
        my $end;
        my $start = $iChunk*($w-1);
        if ($w<$iThreads) {
            $end = ($iChunk*$w)-1;
        } else { # grab the last bit of the list
            $end = $#hse_list;
        };
        my @ShortList = @hse_list[ $start .. $end ];
        ($thread->{"$w"}) = threads->create(\&main,\@ShortList,$x1);
    };
    for(my $w=1; $w<=$iThreads; $w++){
        my @Dummy = $thread->{"$w"}->join();
        $AggkWh = $AggkWh+$Dummy[1]; # Recover the annual energy average output [kWh/yr]
    };
    $pred1 = $AggkWh/$iThreads;
    $AggkWh = 0; # Reinitialize
    $f1 = abs($Target-$pred1);
    # --------------------------------------------------------
    $datestring = localtime();
    print "Finished computing first internal point at $datestring\n";
    # $x2-----------------------------------------------------
    for(my $w=1; $w<=$iThreads; $w++){ # Multithread high
        my $end;
        my $start = $iChunk*($w-1);
        if ($w<$iThreads) {
            $end = ($iChunk*$w)-1;
        } else { # grab the last bit of the list
            $end = $#hse_list;
        };
        my @ShortList = @hse_list[ $start .. $end ];
        ($thread->{"$w"}) = threads->create(\&main,\@ShortList,$x2);
    };
    for(my $w=1; $w<=$iThreads; $w++){
        my @Dummy = $thread->{"$w"}->join();
        $AggkWh = $AggkWh+$Dummy[1]; # Recover the annual energy average output (second variable) [kWh/yr]
    };
    $pred2 = $AggkWh/$iThreads;
    $AggkWh = 0; # Reinitialize
    $f2 = abs($Target-$pred1);
    # --------------------------------------------------------
    $datestring = localtime();
    print "Finished computing second internal point at $datestring\n";
    
    #($f1,$pred1) = main(\@hse_list,$x1);
    #($f2,$pred2) = main(\@hse_list,$x2);
    
    # Loop until convergence or max. iterations
    my $count = 1;
    my $ea;  # Error estimation
    my $xmin;
    my $fmin;
    ITERATOR: while ($count <= $MaxIter) {
        if ($f1 < $f2) { # x1 most likely candidate for minimum
            # Check for convergence
            $ea = (2-$phi)*abs(($xu-$xlow)/$x1)*100; # Error estimate [%]
            $datestring = localtime();
            print "$datestring: Minimum: $f1, Scalar: $x1, Error:$ea\n";
            if ($ea <= $MAXTOL) {
                $xmin = $x1;
                $fmin = $f1;
                last ITERATOR;
            };
            
            # Update the domain
            $xlow=$x2;
            $x2=$x1;
            $f2=$f1;

            # Evaluate the new interior point
            $d = 0.61803*($xu-$xlow);
            $x1=$xlow + $d;
            # $x1-----------------------------------------------------
            for(my $w=1; $w<=$iThreads; $w++){ # Multithread low
                my $end;
                my $start = $iChunk*($w-1);
                if ($w<$iThreads) {
                    $end = ($iChunk*$w)-1;
                } else { # grab the last bit of the list
                    $end = $#hse_list;
                };
                my @ShortList = @hse_list[ $start .. $end ];
                ($thread->{"$w"}) = threads->create(\&main,\@ShortList,$x1);
            };
            for(my $w=1; $w<=$iThreads; $w++){
                my @Dummy = $thread->{"$w"}->join();
                $AggkWh = $AggkWh+$Dummy[1]; # Recover the annual energy average output [kWh/yr]
            };
            $pred1 = $AggkWh/$iThreads;
            $AggkWh = 0; # Reinitialize
            $f1 = abs($Target-$pred1);
            # --------------------------------------------------------
            
        } else { # x2 most likely candidate for minimum
            # Check for convergence
            $ea = (2-$phi)*abs(($xu-$xlow)/$x2)*100; # Error estimate [%]
            $datestring = localtime();
            print "$datestring: Minimum: $f2, Scalar: $x2, Error:$ea\n";
            if ($ea <= $MAXTOL) {
                $xmin = $x2;
                $fmin = $f2;
                last ITERATOR;
            };

            # Update the domain
            $xu=$x1;
            $x1=$x2;
            $f1=$f2;
            # Evaluate the new interior point
            $d = 0.61803*($xu-$xlow);
            $x2 = $xu - $d;
            # $x2-----------------------------------------------------
            for(my $w=1; $w<=$iThreads; $w++){ # Multithread high
                my $end;
                my $start = $iChunk*($w-1);
                if ($w<$iThreads) {
                    $end = ($iChunk*$w)-1;
                } else { # grab the last bit of the list
                    $end = $#hse_list;
                };
                my @ShortList = @hse_list[ $start .. $end ];
                ($thread->{"$w"}) = threads->create(\&main,\@ShortList,$x2);
            };
            for(my $w=1; $w<=$iThreads; $w++){
                my @Dummy = $thread->{"$w"}->join();
                $AggkWh = $AggkWh+$Dummy[1]; # Recover the annual energy average output [kWh/yr]
            };
            $pred2 = $AggkWh/$iThreads;
            $AggkWh = 0; # Reinitialize
            $f2 = abs($Target-$pred2);
            # --------------------------------------------------------
        };
        $count++;
    }; # END ITERATOR

    my $bNonconverge = 0;
    if ($count>$MaxIter) {$bNonconverge = 1};
    if ($bNonconverge) { # Non-convergence
        if ($f1 < $f2) {
            $fmin = $f1;
            $xmin = $x1;
        } else {
            $fmin = $f2;
            $xmin = $x2;
        };
    };
    
    $datestring = localtime();
    print "Finished iterating at $datestring\n";
    print "Minimum scalar $xmin with absolute true difference of $fmin\n\n";
    
    print "Multithreading validation\n";
    #my ($fValid,$pVaild) = main(\@hse_TOT,$xmin);
    # $x2-----------------------------------------------------
    for(my $w=1; $w<=$iThreads; $w++){ # Multithread high
        my $end;
        my $start = $iChunk*($w-1);
        if ($w<$iThreads) {
            $end = ($iChunk*$w)-1;
        } else { # grab the last bit of the list
            $end = $#hse_list;
        };
        my @ShortList = @hse_list[ $start .. $end ];
        ($thread->{"$w"}) = threads->create(\&main,\@ShortList,$xmin);
    };
    for(my $w=1; $w<=$iThreads; $w++){
        my @Dummy = $thread->{"$w"}->join();
        $AggkWh = $AggkWh+$Dummy[1]; # Recover the annual energy average output [kWh/yr]
    };
    my $pVaild = $AggkWh/$iThreads;
    my $fValid = abs($Target-$pVaild);
    # --------------------------------------------------------
    print "Validation complete\n";

    RESOUT: { # Print out results

        my $ResFile = "GoldenSearch_" . "$hse_type" . "_" . "$region" . ".res";
        open (my $RESfh, '>', $ResFile) or die "Cannot print output file $ResFile";
        
        print $RESfh "Target was $Target\n";
        print $RESfh "Minimum target difference of $fmin\n";
        print $RESfh "for scalar $xmin\n";
        print $RESfh "Validation: Difference=$fValid and Average=$pVaild\n";
        if($bNonconverge){print $RESfh "WARNING: max iterations of $MaxIter reached\n"};
        
        close $RESfh;

    }; # END RESOUT

}; # END GOLDEN 

# --------------------------------------------------------------------
# Main calculation subroutine
# --------------------------------------------------------------------
sub main {

    my $list_ref = shift;
    my $fCalibrationScalar = shift;
    my @houses = @$list_ref;
    
    my $kWhAverage; 
    my @AggAnnual=();
    my $TrueError;      # Relative value for true error [%]
    my @Occ_keys=qw(zero one two three four five six);

    # --------------------------------------------------------------------
    # Begin processing each house model for the region and house type
    # --------------------------------------------------------------------
    RECORD: foreach my $hse_name (@houses) {
        my @Occ; # Array to hold occupancy
        my $issue = 0;      # Issue counter
        my $hse_occ = $CREST->{$hse_name}->{'Num_Occ'};
        my @TotalCold=(0) x 525600; # Array to hold the total power draw of all cold appliances [W]
        my @TotalOther=(0) x 525600; # Array to hold the total power draw of all other appliances [W]
        my @TotalCook=(0) x 525600; # Array to hold the annual power draw of range and oven [W]
        my @TotalDry=(0) x 525600; # Array to hold the annual power draw of dryer [W]
        my @TotalALL=(0) x 525600; # Array to hold the total electrical power draw of ALL appliances [W]
        my $MeanActOcc=0;
        my $DayWeekStart = 4; # TODO: Determine day of the week

        # --------------------------------------------------------------------
        # Generate the occupancy profiles
        # --------------------------------------------------------------------
        my $IniState = &setStartState($hse_occ,$occ_strt->{'wd'}->{"$Occ_keys[$hse_occ]"}); # TODO: Determine 'we' or 'wd'
        my $Occ_ref = &OccupancySimulation($hse_occ,$IniState,$DayWeekStart); 
        @Occ = @$Occ_ref;
        
        # Determine the mean active occupancy
        foreach my $Step (@Occ) {
            if($Step>0) {$MeanActOcc++};
        };
        $MeanActOcc=$MeanActOcc/($#Occ+1); # Fraction of time occupants are active

        # --------------------------------------------------------------------
        # Generate Cold appliance profiles
        # --------------------------------------------------------------------
        COLD: {
            my @Cold_key = qw(Main_Refrigerator Secondary_Refrigerator Main_Freezer Secondary_Freezer); # Keys for each type of cold appliance in NN inputs
            foreach my $cold (@Cold_key) { # Determine what cold appliances this dwelling has
                if ($CREST->{$hse_name}->{'data'}->{"$cold"} > 0) { # Dwelling has this type of cold appliance
                    my $ColdSize = $CREST->{$hse_name}->{'data'}->{"$cold"}/28.316847; # Convert size to cu. ft
                    # Determine if fridge or freezer
                    my ($ColdType) = $cold =~ m/_(.*)/;
                    my ($Colduse) = $cold =~ m/(.*)_/;
                    my $ColdRef = $ColdApp->{"$ColdType"}; # Create a hash reference to the data
                    
                    # Randomly select appliance vintage from distribution
                    my $NumVint = $ColdRef->{'dist'}->{'Periods'}->{'intervals'}; # Number of vintage intervals
                    my $InterVint=1; # Index the vintage interval
                    my $fCumulativeP = 0;
                    my $fRand = rand();
                    COLD_VINT: while ($InterVint<=$NumVint) {
                        $fCumulativeP = $fCumulativeP +  $ColdRef->{'dist'}->{$Colduse}->{"_$region"}->{"_$InterVint"};
                        if ($fRand < $fCumulativeP) {last COLD_VINT};
                        $InterVint++;
                    }; # END COLD_VINT
                    my $vintage = &rand_range($ColdRef->{'dist'}->{'Periods'}->{"_$InterVint"}->{'min'},$ColdRef->{'dist'}->{'Periods'}->{"_$InterVint"}->{'max'});
                    
                    # Determine the corresponding UEC for this vintage and appliance type (Refrigerator,Chest_Freezer,Upright_Freezer)
                    my ($UEC,$cType) = &GetUEC($ColdType,$vintage,$ColdSize,$ColdRef->{'eff'});
                    
                    # Generate the annual appliance profile for this appliance (NOTE: The calibration scalar is not applied here)
                    my $CalibCyc = $App->{'Types_Cold'}->{$cType}->{'Base_cycles'}; # Calibrated mean cycles per year
                    my $Cold_Ref = &setColdProfile($UEC,$CalibCyc,$App->{'Types_Cold'}->{$cType}->{'Mean_cycle_L'},$App->{'Types_Cold'}->{$cType}->{'Restart_Delay'});
                    my @ThisCold = @$Cold_Ref;

                    # Update the total cold appliance power draw [W]
                    for (my $k=0; $k<=$#ThisCold;$k++) {
                        $TotalCold[$k]=$TotalCold[$k]+$ThisCold[$k];
                    };
                };
            };
        }; # END COLD
        
        # --------------------------------------------------------------------
        # Generate the profiles of all other appliances (except stove and dryer)
        # --------------------------------------------------------------------
        # Determine the appliance stock of this dwelling
        my @AppStock=();
        my $AppStock_ref = &GetApplianceStock($CREST->{$hse_name}->{'data'},$App->{'Ownership'}->{"_$region"});
        @AppStock=@$AppStock_ref;
        
        foreach my $item (@AppStock) { # For each appliance in the dwelling
            # Load the appropriate appliance data
            my $sUseProfile=$App->{'Types_Other'}->{$item}->{'Use_Profile'}; # Type of usage profile
            my $iMeanCycleLength=$App->{'Types_Other'}->{$item}->{'Mean_cycle_L'}; # Mean length of cycle [min]
            my $iCyclesPerYear=$App->{'Types_Other'}->{$item}->{'Base_cycles'}*$fCalibrationScalar; # Calibrated number of cycles per year
            my $iStandbyPower=$App->{'Types_Other'}->{$item}->{'Standby'}; # Standby power [W]
            my $iRatedPower=$App->{'Types_Other'}->{$item}->{'Mean_Pow_Cyc'}; # Mean power per cycle [W]
            my $iRestartDelay=$App->{'Types_Other'}->{$item}->{'Restart_Delay'}; # Delay restart after cycle [min]
            my $fAvgActProb=$App->{'Types_Other'}->{$item}->{'Avg_Act_Prob'}; # Average activity probability [-]
            my $sOccDepend=$App->{'Types_Other'}->{$item}->{'Avg_Act_Prob'}; # Active occupant dependent

            # Call the appliance simulation
            my $ThisApp_ref = &GetApplianceProfile(\@Occ,$item,$sUseProfile,$iMeanCycleLength,$iCyclesPerYear,$iStandbyPower,$iRatedPower,$iRestartDelay,$fAvgActProb,$Activity,$MeanActOcc,$sOccDepend,$DayWeekStart);
            my @ThisApp = @$ThisApp_ref;

            # Update the TotalOther array [W]
            for(my $k=0;$k<=$#TotalOther;$k++) {
                $TotalOther[$k]=$TotalOther[$k]+$ThisApp[$k];
            };
        
        };

        # --------------------------------------------------------------------
        # Generate the profiles of the stove and dryer
        # --------------------------------------------------------------------
        if($CREST->{$hse_name}->{'data'}->{'Stove'} > 0) { # COOK: There is a stove, compute the profile
            my @CookStock = ();
            push(@CookStock,'Range');
            push(@CookStock,'Oven');
            
            foreach my $item (@CookStock) { # For each appliance in the dwelling
                # Load the appropriate appliance data
                my $sUseProfile=$App->{'Types_Other'}->{$item}->{'Use_Profile'}; # Type of usage profile
                my $iMeanCycleLength=$App->{'Types_Other'}->{$item}->{'Mean_cycle_L'}; # Mean length of cycle [min]
                my $iCyclesPerYear=$App->{'Types_Other'}->{$item}->{'Base_cycles'}*$fCalibrationScalar; # Calibrated number of cycles per year
                my $iStandbyPower=$App->{'Types_Other'}->{$item}->{'Standby'}; # Standby power [W] (reduce the standby, will be scaled up later)
                my $iRatedPower=$App->{'Types_Other'}->{$item}->{'Mean_Pow_Cyc'}; # Mean power per cycle [W]
                my $iRestartDelay=$App->{'Types_Other'}->{$item}->{'Restart_Delay'}; # Delay restart after cycle [min]
                my $fAvgActProb=$App->{'Types_Other'}->{$item}->{'Avg_Act_Prob'}; # Average activity probability [-]
                my $sOccDepend=$App->{'Types_Other'}->{$item}->{'Avg_Act_Prob'}; # Active occupant dependent
    
                # Call the appliance simulation
                my @ThisCook;
                if ($CREST->{$hse_name}->{'stove_fuel'} != 1) { # Stove is not natural gas/propane
                    my $ThisApp_ref = &GetApplianceProfile(\@Occ,$item,$sUseProfile,$iMeanCycleLength,$iCyclesPerYear,$iStandbyPower,$iRatedPower,$iRestartDelay,$fAvgActProb,$Activity,$MeanActOcc,$sOccDepend,$DayWeekStart);
                    @ThisCook = @$ThisApp_ref; # [W]
                } else { # Stove is natural gas. Only consider standby power
                    @ThisCook = ($iStandbyPower) x 525600;
                };
                # Update the TotalCook array [W]
                for(my $k=0;$k<=$#TotalCook;$k++) {
                    $TotalCook[$k]=$TotalCook[$k]+$ThisCook[$k];
                };

            };
        }; # END COOK
        if($CREST->{$hse_name}->{'data'}->{'Clothes_Dryer'} > 0) { # DRY: If there is a dryer, generate the profile
            my $item = 'Clothes_Dryer';
            # Load the appropriate appliance data
            my $sUseProfile=$App->{'Types_Other'}->{$item}->{'Use_Profile'}; # Type of usage profile
            my $iMeanCycleLength=$App->{'Types_Other'}->{$item}->{'Mean_cycle_L'}; # Mean length of cycle [min]
            my $iCyclesPerYear=$App->{'Types_Other'}->{$item}->{'Base_cycles'}*$fCalibrationScalar; # Calibrated number of cycles per year
            my $iStandbyPower=$App->{'Types_Other'}->{$item}->{'Standby'}; # Standby power [W]
            my $iRatedPower=$App->{'Types_Other'}->{$item}->{'Mean_Pow_Cyc'}; # Mean power per cycle [W]
            my $iRestartDelay=$App->{'Types_Other'}->{$item}->{'Restart_Delay'}; # Delay restart after cycle [min]
            my $fAvgActProb=$App->{'Types_Other'}->{$item}->{'Avg_Act_Prob'}; # Average activity probability [-]
            my $sOccDepend=$App->{'Types_Other'}->{$item}->{'Avg_Act_Prob'}; # Active occupant dependent
    
            # Call the appliance simulation
            if ($CREST->{$hse_name}->{'dryer_fuel'} != 1) { # Dryer is not natural gas/propane
                my $ThisApp_ref = &GetApplianceProfile(\@Occ,$item,$sUseProfile,$iMeanCycleLength,$iCyclesPerYear,$iStandbyPower,$iRatedPower,$iRestartDelay,$fAvgActProb,$Activity,$MeanActOcc,$sOccDepend,$DayWeekStart);
                @TotalDry = @$ThisApp_ref; # [W]
            } else { # Dryer is natural gas/propane. Only consider the standby power
                @TotalDry = ($iStandbyPower) x 525600;
            };

        }; # END DRY

        # --------------------------------------------------------------------
        # Sum cold and other appliance vectors
        # ADD THE BASELOAD
        # Determine the annual energy consumption for the dwelling
        # --------------------------------------------------------------------
        my $AnnPow=0; # Total appliance energy consumption for the year for this dwelling[kWh]
        my $ThisBase = $App->{"_$region"}->{"_$hse_type"}->{'Baseload'}; # Constant baseload power [W]
        my $ThisBaseStDev = $App->{"_$region"}->{"_$hse_type"}->{'BaseStdDev'}; # Constant baseload power standard deviation [W]
        $ThisBase = &GetMonteCarloNormalDistGuess($ThisBase,$ThisBaseStDev);
        if($ThisBase<0) {$ThisBase=0};
        for(my $k=0;$k<=$#TotalOther;$k++) {
            $TotalALL[$k]=$TotalOther[$k]+$TotalCold[$k]+$TotalCook[$k]+$TotalDry[$k] + $ThisBase; # [W]
            $AnnPow=$AnnPow+((($TotalALL[$k]*60)/3600)/1000); # [kWh]
        };
        push(@AggAnnual,$AnnPow);
    }; # END RECORD

    # --------------------------------------------------------------------
    # determine the average per household
    # --------------------------------------------------------------------
    my $Agg=0;
    my $Nhousehold = scalar @AggAnnual;
    foreach my $load (@AggAnnual) {
        $Agg=$Agg+$load;
    };
    $kWhAverage = $Agg/$Nhousehold;

    # Determine the absolute true error
    $TrueError = abs($Target-$kWhAverage);
    
    print "True Error $TrueError, average of $kWhAverage kWh\n";
    return($TrueError,$kWhAverage);

}; # END sub main