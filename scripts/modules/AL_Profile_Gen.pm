# ====================================================================
# AL_Profile_Gen.pm
# Author: Adam Wills
# Date: June 2015
# Copyright: Carleton University
# ====================================================================
# The following subroutines are included in the perl module:
# setDryerProfile: Sets the annual dryer electrical usage
# setColdProfile: Sets the annual electrical usage profile for fridge=1, or freezer=2
# ====================================================================

# Declare the package name of this perl module
package AL_Profile_Gen;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Cwd;
use Data::Dumper;
use POSIX qw(ceil floor);

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
#our @EXPORT = qw( setDryerProfile setStoveProfile setOtherProfile setNewBCD);
our @EXPORT = qw(setStartState OccupancySimulation LightingSimulation GetIrradiance GetUEC);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# setStartState
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
#
# REFERENCES: - Richardson, Thomson, Infield, Clifford "Domestic Energy Use:
#               A high-resolution energy demand model". Energy and Buildings, 
#               42, 2010.
#             
# ====================================================================

sub setStartState {
	# Read in inputs
    my ($numOcc, $pdf) = @_;
    
    # Local variables
    my $fRand = rand();
    my $fCumulativeP = 0;
    my $StartActive;
    my @ky = qw(zero one two three four five six);
    
    SET_IT: for (my $i = 0; $i<=6 && exists $pdf->{"$ky[$i]"}; $i++) {
        $fCumulativeP = $fCumulativeP + $pdf->{"$ky[$i]"};
        if ($fRand < $fCumulativeP) {
            $StartActive = $i;
            last SET_IT;
        };
    }; 
    if (!defined $StartActive) {$StartActive = 0};
    
    return ($StartActive);
};

# ====================================================================
# OccupancySimulation
#       This subroutine generates the annual occupancy profile at a 1 
#       minute timestep.
#
# INPUT     numOcc: number of occupants in the house
#           initial: initial number of active occupants for the set
#           dayWeek: initial day of the week [1=Sun, 7=Sat]
# OUTPUT    StartActive: number of active occupants 
#
# REFERENCES: - Richardson, Thomson, Infield, Clifford "Domestic Energy Use:
#               A high-resolution energy demand model". Energy and Buildings, 
#               42, 2010.
#             
# ====================================================================

sub OccupancySimulation {
	# Read in inputs
    my ($numOcc, $initial, $dayWeek) = @_;
    
    # Local variables
    my @Occ = ($initial) x 10; # Array holding number of active occupants in dwelling per minute
    my $bStart=1;
    my $dir = getcwd;
    
    # Check to see if occupancy exceeds model limits
    if ($numOcc>5) { # Reduce the number of occupants to 5
        $numOcc=5;
        # TODO: WARN THE USER
    };
    
    # Load both transition matrices
    my @TRmatWD=(); # Array to hold weekday transition matrix
    my @TRmatWE=(); # Array to hold weekend transition matrix
    
    my $WDfile = $dir . "/Occ_Lighting/tpm" . "$numOcc" . "_wd.csv";
    open my $fh, '<', $WDfile or die "Cannot open $WDfile: $!";
    while (my $dat = <$fh>) {
        chomp $dat;
        push(@TRmatWD,$dat);
    };
    @TRmatWD = @TRmatWD[ 1 .. $#TRmatWD ]; # Trim out header
    close $fh;
    
    my $WEfile = $dir . "/Occ_Lighting/tpm" . "$numOcc" . "_we.csv";
    open my $fhdl, '<', $WEfile or die "Cannot open $WEfile: $!";
    while (my $dat = <$fhdl>) {
        chomp $dat;
        push(@TRmatWE,$dat);
    };
    @TRmatWE = @TRmatWE[ 1 .. $#TRmatWE ]; # Trim out header
    close $fhdl;
    
    YEAR: for (my $i=1; $i<=365; $i++) { # for each day of the year
        # Determine which transition matrix to use
        my $tDay; 
        my @TRmat;
        if ($dayWeek>7){$dayWeek=1};
        if ($dayWeek == 1 || $dayWeek == 7) {
            @TRmat = @TRmatWE;
        } else { 
            @TRmat = @TRmatWD;
        };

        if ($bStart) { # first call, first 10 minutes don't matter
            @TRmat = @TRmat[ 7 .. $#TRmat ];
            $bStart=0;
        };
        DAY: for (my $j=0; $j<=$#TRmat; $j=$j+7) { # Cycle through each period in the matrix
            my $current = $Occ[$#Occ]; # Current occupancy
            # Find the appropriate distribution data
            my $k=$j+$current;
            my $dist = $TRmat[$k];
            chomp $dist;
            my @data = split /,/, $dist;
            @data = @data[ 2 .. $#data ]; # Trim out the index values
            my $fCumulativeP=0; # Cumulative probability for period
            my $fRand = rand();
            my $future=0; # future occupancy
            TEN: while ($future < $numOcc) {
                $fCumulativeP=$fCumulativeP+$data[$future];
                if ($fRand < $fCumulativeP) {
                    last TEN;
                };
                $future++;
            }; # END TEN
            
            # Update the Occupancy array
            for (my $m=0; $m<10; $m++) { # This will be the occupancy for the next ten minutes
                push(@Occ,$future);
            };
        }; # END DAY
        $dayWeek++;
    }; # END YEAR 

    return (\@Occ);
};

# ====================================================================
# LightingSimulation
#       This subroutine generates the annual occupancy profile at a 1 
#       minute timestep.
#
# INPUT     ref_Occ: Annual dwelling occupancy at 1 min timestep
#           climate: EPW weather file for house
#           fBulbs: Array holding wattage for each lamp [W]
#           fCalibrationScalar: Calibration scalar for lighting model
#           MeanThresh: Mean threshold for light ON [W/m2]
#           STDThresh: Std. dev for light ON [W/m2]
# OUTPUT    Light: Annual lighting power at 1 min timestep [kW]
#           AnnPow: Annual power consumption of dwelling for lighting [kWh]
#
# REFERENCES: - Richardson, Thomson, Infield, Delahunty "Domestic Lighting:
#               A high-resolution energy demand model". Energy and Buildings, 
#               41, 2009.
# ====================================================================

sub LightingSimulation {
    # Read in inputs
    my ($ref_Occ, $Irr_ref, $fBulbs_ref, $fCalibrationScalar,$MeanThresh,$STDThresh) = @_;
    my @Occ = @$ref_Occ;
    my @Irr = @$Irr_ref;
    my @fBulbs = @$fBulbs_ref;
    
    if ($#Occ != $#Irr) {die "Number of occupancy and irradiance timesteps do not match"};
    
    # Set local variables
    my $Tsteps = scalar @Occ;
    my $SMALL = 1.0e-20;
    
    # Declare output
    my @Light=(0) x $Tsteps;
    my $AnnPow=0;

    # Determine the irradiance threshold of this house
    my $iIrradianceThreshold = GetMonteCarloNormalDistGuess($MeanThresh,$STDThresh);

    # Assign weightings to each bulb
    BULB: for (my $i=0;$i<=$#fBulbs;$i++) { # For each dwelling bulb
        # Determine this bulb's relative usage weighting
        my $fRand = rand();
        if ($fRand < $SMALL) {$fRand = $SMALL}; # Avoid domain errors
        my $fCalibRelUseW = -1*$fCalibrationScalar*log($fRand);

        # Calculate this bulb's usage for each timestep
        my $iTime=0;
        TIME: while ($iTime<=$#Occ) {
            # Is this bulb switched on to start with?
            # This concept is not implemented in this example.
            # The simplified assumption is that all bulbs are off to start with.
            
            # First determine if there are any occupants active for a switch-on event
            if ($Occ[$iTime]==0) { # No occupants, jump to next period
                $iTime++;
                next TIME;
            };
            # Determine if the bulb switch-on condition is passed
            # ie. Insuffient irradiance and at least one active occupant
            # There is a 5% chance of switch on event if the irradiance is above the threshold
            my $bLowIrradiance;
            if (($Irr[$iTime] < $iIrradianceThreshold) || (rand() < 0.05)) {
                $bLowIrradiance = 1;
            } else {
                $bLowIrradiance = 0;
            };
            
            # Get the effective occupancy for this number of active occupants to allow for sharing
            my $fEffectiveOccupancy = GetEffectiveOccupancy($Occ[$iTime]);

            # Check the probability of a switch on at this time
            if ($bLowIrradiance && (rand() < ($fEffectiveOccupancy*$fCalibRelUseW))) { # This is a switch on event
                # Determine how long this bulb is on for
                my $iLightDuration = GetLightDuration();
                
                DURATION: for (my $j=1;$j<=$iLightDuration;$j++) {
                    # Range Check
                    if ($iTime > $#Occ) {last TIME};
                    
                    # If there are no active occupants, turn off the light and increment the time
                    if ($Occ[$iTime] <=0) {
                        $iTime++;
                        next TIME;
                    };
                    
                    # Store the demand
                    $Light[$iTime] = $Light[$iTime]+($fBulbs[$i]/1000); # [kW]
                    
                    # Increment the time
                    $iTime++;
                }; # END DURATION
                
            } else { # The bulb remains off
                $iTime++;
            };
        }; # END TIME 
    }; # END BULB
    
    # Integrate bulb usage to find annual consumption, and scale to kW
    for (my $k=0; $k<=$#Light; $k++) {
        $AnnPow=$AnnPow+($Light[$k]*60); # [kJ]
    };
    
    # Express annual consumption in kWh
    $AnnPow=$AnnPow/3600;

    return(\@Light, $AnnPow);
};

# ====================================================================
# GetIrradiance
#       This subroutine loads the irradiance data and returns it 
#
# INPUT     file: path and file name of input
# OUTPUT    Irr: Array holding the irradiance data [W/m2]
#
# ====================================================================

sub GetIrradiance {
    # Read in inputs
    my ($file) = @_;
    
    # Declare output
    my @Irr=();
    
    open my $fh, '<', $file or die "Cannot open $file: $!";
    my $i=0;
    RAD: while (my $dat = <$fh>) {
            if ($i<2) { # Header data, skip
                $i++;
                next RAD;
            };
            chomp $dat;
            my @temp = split /\t/, $dat,2;
            $temp[1] = sprintf("%.10g", $temp[1]);
            push(@Irr, $temp[1]); 
    }; # END RAD
    close $fh;
    
    pop(@Irr); # Trim out last timestep

    return(\@Irr);
};

# ====================================================================
#  LOCAL SUBROUTINES
# ====================================================================

# ====================================================================
# GetMonteCarloNormalDistGuess
#   This subroutine randomly selects a value from a normal distribution.
#   Inputs are the mean and standard deviation
# ====================================================================
sub GetMonteCarloNormalDistGuess {
    my ($dMean, $dSD) = @_;
    my $iGuess=0;
    my $bOk;
    
    if($dMean == 0) {
        $bOk = 1;
    } else {
        $bOk = 0;
    };
    
    while (!$bOk) {
        $iGuess = (rand()*($dSD*8))-($dSD*4)+$dMean;
        my $px = (1/($dSD * sqrt(2*3.14159))) * exp(-(($iGuess - $dMean) ** 2) / (2 * $dSD * $dSD));

        if ($px >= rand()) {$bOk=1};

    };

    return $iGuess;
};

# ====================================================================
# EffectiveOccupancy
#   This subroutine determines the effective occupancy
# ====================================================================
sub GetEffectiveOccupancy {
    my ($Occ) = @_; # Number of occupants active

    my $EffOcc;
    
    if ($Occ==0) {
        $EffOcc=0;
    } elsif ($Occ==1) {
        $EffOcc=1;
    } elsif ($Occ==2) {
        $EffOcc=1.528;
    } elsif ($Occ==3) {
        $EffOcc=1.694;
    } elsif ($Occ==4) {
        $EffOcc=1.983;
    } elsif ($Occ==5) {
        $EffOcc=2.094;
    } else {
        die "Number of occupants $Occ exceeds model limits";
    };

    return $EffOcc;
};

# ====================================================================
# GetLightDuration
#   Determines the lighting event duration
#   REFERENCE: - Stokes, Rylatt, Lomas "A simple model of domestic lighting
#                demand". Energy and Buildings, 36(2), 2004. 
# ====================================================================
sub GetLightDuration {

    # Decalre the output
    my $Duration;
    
    # Lighting event duration model data
    my $cml;
    $cml->{'1'}->{'lower'}=1;
    $cml->{'1'}->{'upper'}=1;
    $cml->{'1'}->{'cml'}=0.111111111;
    
    $cml->{'2'}->{'lower'}=2;
    $cml->{'2'}->{'upper'}=2;
    $cml->{'2'}->{'cml'}=0.222222222;
    
    $cml->{'3'}->{'lower'}=3;
    $cml->{'3'}->{'upper'}=4;
    $cml->{'3'}->{'cml'}=0.222222222;
    
    $cml->{'4'}->{'lower'}=5;
    $cml->{'4'}->{'upper'}=8;
    $cml->{'4'}->{'cml'}=0.333333333;
    
    $cml->{'5'}->{'lower'}=9;
    $cml->{'5'}->{'upper'}=16;
    $cml->{'5'}->{'cml'}=0.444444444;
    
    $cml->{'6'}->{'lower'}=17;
    $cml->{'6'}->{'upper'}=27;
    $cml->{'6'}->{'cml'}=0.555555556;
    
    $cml->{'7'}->{'lower'}=28;
    $cml->{'7'}->{'upper'}=49;
    $cml->{'7'}->{'cml'}=0.666666667;
    
    $cml->{'8'}->{'lower'}=50;
    $cml->{'8'}->{'upper'}=91;
    $cml->{'8'}->{'cml'}=0.888888889;
    
    $cml->{'8'}->{'lower'}=92;
    $cml->{'8'}->{'upper'}=259;
    $cml->{'8'}->{'cml'}=1.0;
    
    my $r_one = rand();
    
    RANGE: for (my $j=1;$j<=9;$j++) {
        if ($r_one < $cml->{"$j"}->{'cml'}) {
            my $r_two = rand();
            $Duration = ($r_two * ($cml->{"$j"}->{'upper'}-$cml->{"$j"}->{'lower'}))+$cml->{"$j"}->{'lower'};
            $Duration = sprintf "%.0f", $Duration; # Round to nearest integer
            last RANGE;
        };
    }; # END RANGE

    return $Duration;
};

# ====================================================================
# GetUEC
#   This subroutine determines the UEC of cold appliances of specified
#   type, vintage, and size. Fridge data is read directly from the HASH.
#   Freezers are not sorted by size but type. The type is randomly selected
#   from the distribution, and the associated UEC is selected.
#
#   INPUTS:     type: Type of cold appliance (Refrigerator or Freezer)
#               vintage: Year of fridge manufacture
#               size: Size of the cold appliance [cu. ft.]
#               ColdHash: Hash holding the efficiency data
#   OUTPUTS     UEC: Unit energy consumption [kWh/yr]
# ====================================================================
sub GetUEC {
    # Read in the inputs
    my $type = shift;
    my $vintage = shift;
    my $size = shift;
    my $ColdHash = shift;
    
    # Declare the outputs
    my $UEC;
    
    # Determine the type of cold appliance
    if ($type =~ m/Refrigerator/) { # Fridge
        if ($size > $ColdHash->{'Sizes'}->{$ColdHash->{'Sizes'}->{'intervals'}}->{'max'}) {
            $size = $ColdHash->{'Sizes'}->{$ColdHash->{'Sizes'}->{'intervals'}}->{'max'};
        };
        my $i = 1;
        while ($ColdHash->{'Sizes'}->{"$i"}->{'max'} < $size) { # Find consumption data for appliance size
            $i++;
        };
        
        $UEC = $ColdHash->{'Eff'}->{"$vintage"}->{"$i"};
        
    } elsif ($type =~ m/Freezer/) { # Freezer
        # Select a freezer type using distribution for particular vintage
        my $U = rand(100);
        my $j=0;
        my $fType;
        
        foreach my $Ind (keys (%{$ColdHash->{'types'}->{"$vintage"}})) {
            $j=$j+$ColdHash->{'types'}->{"$vintage"}->{"$Ind"};
            if ($j > $U) {
                $fType = $Ind;
                last;
            };
        };
        
        $UEC = $ColdHash->{'Eff'}->{"$vintage"}->{"$fType"};
    
    } else { # Error
        die "Invalid cold appliance type\n";
    };
    
    return $UEC;
};

# ====================================================================
# setColdProfile
#       This subroutine uses a top-down approach to generate high-resolution
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     UEC: Unit energy consumption [kWh/yr]
#           iCyclesPerYear: number of cycles per year
#           iMeanCycleLength: mean cycle length [min]
#           iRestartDelay: delay restart after cycle [min]
# OUTPUT    Cold: Annual electrical consumption profile of cold appliance [kW]
# ====================================================================

sub setColdProfile {
    # Declare inputs
    my $UEC = shift;
    my $iCyclesPerYear = shift;
    my $iMeanCycleLength = shift;
    my $iRestartDelay = shift;
    
    # Local variables
    my $fPower; # Power draw when cycle is on [kW]
    my $dCalibrate; # Calibration value to determine switch-on events
    my $iRestartDelayTimeLeft; # Counter to hold time left in the delay restart
    
    # Declare outputs
    my @Cold=(0) x 525600; 
    
    # Determine time appliance is running in a year [min]
    my $Trunning=$iCyclesPerYear*$iMeanCycleLength;
    
    # Determine the minutes in a year when an event can occur
    my $Ms = 525600-($Trunning+($iCyclesPerYear*$iRestartDelay));
    
    # Determine the mean time between start events [min]
    my $MT=$Ms/$iCyclesPerYear;
    $dCalibrate=1/$MT;
    
    # Estimate the cycle power [kW]
    $fPower=$UEC/($Trunning/60);
    
    # ====================================================================
    # Begin generating profile
    # ====================================================================
    # Randomly delay the start of appliances that have a restart delay (e.g. cold appliances with more regular intervals)
    $iRestartDelayTimeLeft = int(rand()*$iRestartDelay*2); # Weighting is 2 just to provide some diversity
    my $iCycleTimeLeft = 0;
    my $iMinute = 0;
    
    MINUTE: while ($iMinute < 525600) { # For each minute of the year
        if ($iCycleTimeLeft <= 0 && $iRestartDelayTimeLeft > 0) { # If this appliance is off having completed a cycle (ie. a restart delay)
            # Decrement the cycle time left
            $iRestartDelayTimeLeft--;
        } elsif ($iCycleTimeLeft <= 0) { # Else if this appliance is off
            if (rand() < $dCalibration) { # Start Appliance
                $Cold[$iMinute] = $fPower;
                $iRestartDelayTimeLeft = $iRestartDelay;
                $iCycleTimeLeft = $iMeanCycleLength-1;
            };
        } else { # The appliance is on
            $Cold[$iMinute] = $fPower;
            $iCycleTimeLeft--;
        };
        $iMinute++;
    }; # END MINUTE
    
    return(\@Cold);
};

# Final return value of one to indicate that the perl module is successful
1;