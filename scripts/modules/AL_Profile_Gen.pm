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
use Switch;

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(setStartState OccupancySimulation LightingSimulation GetIrradiance GetUEC setColdProfile ActiveStatParser GetApplianceStock);
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
#           cType: String indicating appliance type (Refrigerator Upright_Freezer Chest_Freezer)
# ====================================================================
sub GetUEC {
    # Read in the inputs
    my $type = shift;
    my $vintage = shift;
    my $size = shift;
    my $ColdHash = shift;
    
    # Declare the outputs
    my $UEC;
    my $cType;
    
    # Determine the type of cold appliance
    if ($type =~ m/Refrigerator/) { # Fridge
        my $sizeInd = $ColdHash->{'Sizes'}->{'intervals'};
        if ($size > $ColdHash->{'Sizes'}->{"_$sizeInd"}->{'max'}) {
            $size = $ColdHash->{'Sizes'}->{"_$sizeInd"}->{'max'};
        };
        my $i = 1;
        while ($ColdHash->{'Sizes'}->{"_$i"}->{'max'} < $size) { # Find consumption data for appliance size
            $i++;
        };
        
        $UEC = $ColdHash->{'Eff'}->{"_$vintage"}->{"_$i"};
        $cType = 'Refrigerator';
        
    } elsif ($type =~ m/Freezer/) { # Freezer
        # Select a freezer type using distribution for particular vintage
        my $U = rand(100);
        my $j=0;
        my $fType;
        
        foreach my $Ind (keys (%{$ColdHash->{'types'}->{"_$vintage"}})) {
            $j=$j+$ColdHash->{'types'}->{"_$vintage"}->{"_$Ind"};
            if ($j > $U) {
                $fType = $Ind;
                last;
            };
        };
        
        $UEC = $ColdHash->{'Eff'}->{"_$vintage"}->{"_$fType"};
        
        if (($fType == 10) || ($fType == 18)) {
            $cType = 'Chest_Freezer';
        } else {
            $cType = 'Upright_Freezer';
        };
    
    } else { # Error
        die "Invalid cold appliance type\n";
    };
    
    return ($UEC,$cType);
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
    my $cType;
    
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
            if (rand() < $dCalibrate) { # Start Appliance
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

# ====================================================================
# ActiveStatParser
#       This subroutine uses a top-down approach to generate high-resolution
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     path: String, path to the activity stats file
# OUTPUT    Activity: HASH holding the activity data
# ====================================================================

sub ActiveStatParser {
    # Declare inputs
    my $path = shift;
    
    # Local variables
    my $fh;     # File handle
    my $day='wd';    # String to hold weekend or weekday
    my $NOcc;        # Number of occupants
    my $Act;         # String, activity type

    # Declare outputs
    my $Activity;
    
    
    open($fh,'<',$path) or die "Could not open file '$path' $!";
    # Read data line by line
    while (my $row = <$fh>) {
        chomp $row;
        my @data = split /,/, $row;
        if ($data[0]>0) {$day='we'};
        $NOcc = $data[1]; # Get active occupant count
        $Act = $data[2];  # Get the activity name
        @data = @data[ 3 .. $#data ]; # trim out the above data
        $Activity->{$day}->{"$NOcc"}->{$Act} = \@data; # Store the statistics
    };

    return($Activity);
};

# ====================================================================
# GetApplianceStock
#       This subroutine uses a top-down approach to generate high-resolution
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     NN: HASH containing the NN inputs from the CHREM
# OUTPUT    stock: Array of strings containing the appliance stock for this dwelling
# ====================================================================

sub GetApplianceStock {
    # Declare inputs
    my $NN = shift;
    my $region = shift;
    
    # Local variables

    # Declare outputs
    my @stock=();
    
    # Determine appliances from CHREM NN inputs
    
    # Presence only
    if($NN->{'Stove'} > 0) {
        push(@stock,'Range');
        push(@stock,'Oven');
    };
    if($NN->{'Microwave'} > 0) {push(@stock,'Microwave')};
    if($NN->{'Clothes_Dryer'} > 0) {push(@stock,'Clothes_Dryer')};
    if($NN->{'Dishwasher'} > 0) {push(@stock,'Dishwasher')};
    if($NN->{'Fish_Tank'} > 0) {push(@stock,'Fish_Tank')};
    if($NN->{'Clothes_Washer'} > 0) {push(@stock,'Clothes_Washer')};
    if($NN->{'Sauna'} > 0) {push(@stock,'Sauna')};
    if($NN->{'Jacuzzi'} > 0) {push(@stock,'Jacuzzi')};
    if($NN->{'Central_Vacuum'} > 0) {push(@stock,'Central_Vacuum')};
    
    # Counts
    if($NN->{'Color_TV'} > 0) {
        for(my $i=1; $i<=$NN->{'Color_TV'};$i++) {
            push(@stock,'TV');
        };
    };
    if($NN->{'Computer'} > 0) {
        for(my $i=1; $i<=$NN->{'Computer'};$i++) {
            push(@stock,'Computer');
        };
    };
    if($NN->{'VCR'} > 0) {
        for(my $i=1; $i<=$NN->{'VCR'};$i++) {
            push(@stock,'VCR');
        };
    };
    if($NN->{'BW_TV'} > 0) {
        for(my $i=1; $i<=$NN->{'BW_TV'};$i++) {
            push(@stock,'TV');
        };
    };
    if($NN->{'CD_Player'} > 0) {
        for(my $i=1; $i<=$NN->{'CD_Player'};$i++) {
            push(@stock,'CD_Player');
        };
    };
    if($NN->{'Stereo'} > 0) {
        for(my $i=1; $i<=$NN->{'Stereo'};$i++) {
            push(@stock,'Stereo');
        };
    };
    
    
    # TODO: Randomly distribute the CREST appliances

    return(\@stock);
};

# ====================================================================
# GetApplianceProfile
#       This subroutine uses generates the 
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     Occ_ref: Reference to array holding annual occupancy data
#           item: String, name of the appliance
#           sUseProfile: String indicating the usage type
#           iMeanCycleLength: Mean length of each cycle [min]
#           iCyclesPerYear: Calibrated number of cycles per year
#           iStandbyPower: Standby power [W]
#           iRatedPower: Rated power during cycles [W]
#           iRestartDelay: Delay prior to starting a cycle [min]
#           fAppCalib: Calibration scalar [-]
#           ActStat: HASH holding the activity statistics
#           dayWeek: day of the week [1=Sunday, 7=Saturday]
# OUTPUT    Profile: The power consumption for this appliance at a 1-minute timestep [kW]
# ====================================================================

sub GetApplianceProfile {
    # Declare inputs
    my $Occ_ref = shift;
    my @Occ = @$Occ_ref;
    my $item = shift;
    my $sUseProfile = shift;
    my $iMeanCycleLength = shift;
    my $iCyclesPerYear = shift;
    my $iStandbyPower = shift;
    my $iRatedPower = shift;
    my $iRestartDelay = shift;
    my $fAvgActProb = shift;
    my $ActStat = shift;
    my $MeanActOcc = shift;
    my $dayWeek = shift;
    
    # Determine the calibration scalar
    my $fAppCalib = ApplianceCalibrationScalar($iCyclesPerYear,$iMeanCycleLength,$MeanActOcc,$iRestartDelay);
    
    # Local variables
    my $iCycleTimeLeft = 0;
    my $sDay;   # String to indicate weekday or weekend
    my $iYear=0; # Counter for minute of the year
    my $iRestartDelayTimeLeft = rand()*$iRestartDelay*2; # Randomly delay the start of appliances that have a restart delay
    my $bDayDep=1; # Flag indicating if appliance is dependent on weekend/weekday (default is true)
    my @PDF=(); # Array to hold the ten minute interval usage statistics for the appliance
    
    # Declare outputs
    my @Profile=(0) x 525600;
    
    # Make the rated power variable over a normal distribution to provide some variation
    $iRatedPower = GetMonteCarloNormalDistGuess($iRatedPower,($iRatedPower/10));
    
    # Determine if appliance operation is weekday/weekend dependent
    if($sUseProfile =~ m/Active_Occ/ || $sUseProfile =~ m/Level/) {$bDayDep=0};
    
    # Start looping through each day of the year
    DAY: for(my $iDay=1;$iDay<=365;$iDay++) {
        my $DayStat; # HASH reference for current day
        
        # If this appliance depends on day type, get the relevant activity statistics
        if($bDayDep) { 
            if($dayWeek>7){$dayWeek=1};
            if($dayWeek == 1 || $dayWeek == 7) { # Weekend
                $sDay = 'we';
            } else { # Weekday
                $sDay = 'wd';
            };
            $DayStat=$ActStat->{$sDay};
        };
        
        # For each 10 minute period of the day
        TEN_MIN: for(my $iTenMin=0;$iTenMin<144;$iTenMin++) {
            # For each minute of the day
            MINUTE: for(my $iMin=0;$iMin<10;$iMin++) {
                # Default the power draw to standby
                $Profile[$iYear]=$iStandbyPower;
                
                # If this appliance is off having completed a cycle (ie. a restart delay)
                if ($iCycleTimeLeft <= 0 && $iRestartDelayTimeLeft > 0) {
                    $iRestartDelayTimeLeft--; # Decrement the cycle time left
                    
                # Else if this appliance is off    
                } elsif ($iCycleTimeLeft <= 0) {
                    # There must be active occupants, or the profile must not depend on occupancy for a start event to occur
                    if (($Occ[$iYear] > 0 && $sUseProfile !~ m/Custom/) || $sUseProfile =~ m/Level/) {
                        # Variable to store the event probability (default to 1)
                        my $dActivityProbability = 1;
                        
                        # For appliances that depend on activity profiles
                        if (($sUseProfile !~ m/Level/) && ($sUseProfile !~ m/Active_Occ/) && ($sUseProfile !~ m/Custom/)) {
                            # Get the probability for this activity profile for this time step
                            my $CurrOcc = $Occ[$iYear]; # Current occupancy this timestep
                            my $Prob_ref = $DayStat->{"$CurrOcc"}->{$sUseProfile};
                            my @Prob=@$Prob_ref;
                            $dActivityProbability = $Prob[$iTenMin];
                        };
                        
                        # If there is seasonal variation, adjust the calibration scalar
                        if ($item =~ m/Clothes_Dryer/) { # Dryer usage varies seasonally
                            my $fAmp =  20.5; # based on difference in average loads/week winter/summer (SHEU 2011);
                            my $fModCyc = ($fAmp*sin(((2*3.14159265*$iDay)/365)-((1053*3.14159265)/730)))+$iCyclesPerYear;
                            $fAppCalib = ApplianceCalibrationScalar($fModCyc,$iMeanCycleLength,$MeanActOcc,$iRestartDelay); #Adjust the calibration
                        }; # elsif .. (Other appliances)
                        
                        # Check the probability of a start event
                        if (rand() < ($fAppCalib*$dActivityProbability)) {
                            ($iCycleTimeLeft,$iRestartDelayTimeLeft,$Profile[$iYear]) = StartAppliance($item,$iRatedPower,$iMeanCycleLength,$iRestartDelay,$iStandbyPower);
                        };
                    } elsif ($sUseProfile =~ m/Custom/) {
                        # PLACE CODE HERE FOR CUSTUM APPLIANCE BEHAVIOUR
                        # THIS CODE BLOCK DETERMINES HOW CUSTOM APPLIANCE IS SWITCHED ON
                        # ($iCycleTimeLeft,$iRestartDelayTimeLeft,$Profile[$iYear]) = StartCustom($item,$iRatedPower,$iMeanCycleLength,$iRestartDelay,$iStandbyPower);
                    };

                # The appliance is on - if the occupants become inactive, switch off the appliance
                } else {
                    if (($Occ[$iYear] == 0) && ($sUseProfile !~ m/Level/) && ($sUseProfile !~ m/Act_Laundry/) && ($item !~ m/Dishwasher/) && ($sUseProfile !~ m/Custom/)) {
                        # Do nothing. The activity will be completed upon the return of the active occupancy.
                        # Note that LEVEL means that the appliance use is not related to active occupancy.
                        # Note also that laundry appliances do not switch off upon a transition to inactive occupancy.
                        # The original CREST model was modified to include dishwashers here as well
                    } elsif ($sUseProfile !~ m/Custom/) { 
                        # Set the power
                        $Profile[$iYear]=GetPowerUsage($item,$iRatedPower,$iCycleTimeLeft,$iStandbyPower);
                        
                        # Decrement the cycle time left
                        $iCycleTimeLeft--;
                    } else { # Custum Use profile
                        # PLACE CODE HERE FOR CUSTUM APPLIANCE BEHAVIOUR
                        # THIS CODE BLOCK DETERMINES HOW CUSTOM APPLIANCE BEHAVES 
                        # WHILE IT IS ON
                        # $Profile[$iYear]=GetCustomUsage($item,$iRatedPower,$iCycleTimeLeft,$iMeanCycleLength,$iStandbyPower);
                    };
                };

                $iYear++; # Increment the minute of the year
            }; # END MINUTE
        }; # END TEN_MIN
        $dayWeek++; # Increment the day of the week
    }; # END DAY

    return(\@Profile);
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
# StartAppliance
#   Start a cycle for the current appliance
# ====================================================================
sub StartAppliance {
    
    # Declare inputs
    my $item = shift;
    my $iRatedPower = shift;
    my $iMeanCycleLength = shift;
    my $iRestartDelay=shift;
    my $iStandbyPower=shift;

    # Declare outputs
    my $iCycleTimeLeft = CycleLength($item,$iMeanCycleLength);
    my $iRestartDelayTimeLeft=$iRestartDelay;
    my $iPower = GetPowerUsage($item,$iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    
    $iCycleTimeLeft--;

    return($iCycleTimeLeft,$iRestartDelayTimeLeft,$iPower);
};

# ====================================================================
# CycleLength
#   Determine the cycle length of the appliance
# ====================================================================
sub CycleLength {
    
    # Declare inputs
    my $item = shift;
    my $iMeanCycleLength = shift;

    # Declare outputs
    my $CycleLen=$iMeanCycleLength;
    
    if($item =~ m/TV/) { # If the appliance is a television
        # The cycle length is approximated by the following function
        # Average time Canadians spend watching TV is 2.1 hrs (Stats Can: General 
        # social survey (GSS), average time spent on various activities for the 
        # population aged 15 years and over, by sex and main activity. 2010)
        $CycleLen=int(122 * ((0 - log(1 - rand())) ** 1.1));
        
    # Currently these profiles are fixed. Override user input to length of
    # each static cycle
    } elsif ($item =~ m/Clothes_Washer/) {
        $CycleLen=;
    } elsif ($item =~ m/Clothes_Dryer/) {
        $CycleLen=75;
    } elsif ($item =~ m/Dishwasher/) {
        $CycleLen=124;
    };

    return($CycleLen);
};

# ====================================================================
# GetPowerUsage
#   Some appliances have a custom (variable) power profile depending on the time left
# ====================================================================
sub GetPowerUsage {
    
    # Declare inputs
    my $item = shift;
    my $iRatedPower = shift;
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs (Default to rated power)
    my $PowerUsage=$iRatedPower;
    
    if($item =~ m/Clothes_Washer/) { # If the appliance is a washer (peak 500 W)
        #$PowerUsage=GetPowerWasher($iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    } elsif($item =~ m/Clothes_Dryer/) { # If the appliance is a dryer (peak 5535 W)
        $PowerUsage=GetPowerDryer($iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    } elsif($item =~ m/Dishwasher/) { # If the appliance is a dishwasher (peak 1300 W)
        $PowerUsage=GetPowerDish($iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    };

    return($PowerUsage);
};

# ====================================================================
# GetPowerDryer
#   This subroutine generates the dryer profile. Note that it is a fixed
#   profile. The profile is a 73 minute cycle which consumes 7935 kJ of
#   energy. The profile is taken from H12 from the paper:
# REFERENCES: - Saldanha, Beausoleil-Morrison "Measured end-use electric load
#               profiles for 12 Canadian houses at high temporal resolution."
#               Energy and Buildings, 49, 2012.
#   The model of the dryer is Kenmore 110.C64852301
# ====================================================================
sub GetPowerDryer {
    
    # Declare inputs
    my $iRatedPower = shift; # Peak power demand
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs
    my $PowerUsage;
    
    # Declare local variables
    my @Profile = (0.674796748,0.951219512,0.991869919,0.967479675,0.991869919,1,
    1,1,1,0.991869919,0.991869919,0.983739837,0.975609756,0.975609756,0.528455285,
    0.203252033,0.951219512,0.951219512,0.691056911,0.056910569,0.739837398,
    0.967479675,0.349593496,0.056910569,0.74796748,0.804878049,0.056910569,
    0.056910569,0.341463415,0.333333333,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.048780488,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.06504065,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.06504065,0.056910569,0.056910569,0.06504065,
    0.056910569,0.056910569,0.056910569,0.06504065,0.056910569,0.032520325); # 1-minute profile for dryer
    my $iTotalCycleTime = scalar @Profile;
    my $index = $iTotalCycleTime - $iCycleTimeLeft;
    
    if (($index<0) || ($index>$#Profile)) {
        $PowerUsage = $iStandbyPower;
    } else {
        $PowerUsage=$iRatedPower*$Profile[$index];
    };
    
    return($PowerUsage);
};

# ====================================================================
# GetPowerWasher
#   This subroutine generates the clothes washer profile. Note that it is a
#   fixed profile. The profile is a 73 minute cycle which consumes 7987 kJ of
#   energy. The profile is taken from H12 from the paper:
# REFERENCES: - Saldanha, Beausoleil-Morrison "Measured end-use electric load
#               profiles for 12 Canadian houses at high temporal resolution."
#               Energy and Buildings, 49, 2012.
# ====================================================================
sub GetPowerWasher {
    
    # Declare inputs
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs
    my $PowerUsage;
    
    # Declare local variables
    my @Profile = (); # 1-minute profile for dryer
    my $iTotalCycleTime = scalar @Profile;
    my $index = $iTotalCycleTime - $iCycleTimeLeft;

    if (($index<0) || ($index>$#Profile)) {
        $PowerUsage = $iStandbyPower;
    } else {
        $PowerUsage=$Profile[$index];
    };
    
    return($PowerUsage);
};

# ====================================================================
# GetPowerDish
#   This subroutine generates the dishwasher profile. The profile is a 
#   124 minute cycle which consumes 5900 kJ of energy. The profile is 
#   scaled based on the rated input power. The profile is taken from
#   H12 from the paper:
# REFERENCES: - Saldanha, Beausoleil-Morrison "Measured end-use electric load
#               profiles for 12 Canadian houses at high temporal resolution."
#               Energy and Buildings, 49, 2012.
#   The model of the dishwasher is Kenmore 665.13732K601 
# ====================================================================
sub GetPowerDish {
    
    # Declare inputs
    my $iRatedPower = shift; # Peak power demand
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs
    my $PowerUsage;
    
    # Declare local variables
    my @Profile = (0.153846154,0.153846154,0.153846154,0.153846154,0.153846154,
    0.153846154,0.153846154,0.153846154,0.153846154,0.153846154,0.153846154,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615); # 1-minute profile for dishwasher
    my $iTotalCycleTime = scalar @Profile;
    my $index = $iTotalCycleTime - $iCycleTimeLeft;
    
    if (($index<0) || ($index>$#Profile)) {
        $PowerUsage = $iStandbyPower;
    } else {
        $PowerUsage=$iRatedPower*$Profile[$index];
    };
    
    return($PowerUsage);
};

# ====================================================================
# ApplianceCalibrationScalar
#   This subroutine determines the appliance calibration scalar
# ====================================================================
sub ApplianceCalibrationScalar {
    
    # Declare inputs
    my $iCyclesPerYear = shift;
    my $iMeanCycleLength = shift;
    my $MeanActOcc = shift;
    my $iRestartDelay = shift;
    
    # Declare outputs
    my $fAppCalib;

    # Determine the calibration scalar for this appliance
    my $iTimeRunYr = $iCyclesPerYear*$iMeanCycleLength; # Time spent running per year [min]
    my $iMinutesCanStart; # Minutes in a year when an event can start
    if($sOccDepend =~ m/YES/) { # Appliance is active occupant dependent
        $iMinutesCanStart = (525600*$MeanActOcc)-($iTimeRunYr+($iCyclesPerYear*$iRestartDelay));
    } else { # Appliance is not active occupant dependent
        $iMinutesCanStart = 525600-($iTimeRunYr+($iCyclesPerYear*$iRestartDelay));
    };
    my $fMeanCanStart=$iMinutesCanStart/$iCyclesPerYear; # Mean time between start events given occupancy [min]
    my $fLambda = 1/$fMeanCanStart;
    $fAppCalib = $fLambda/$fAvgActProb; # Calibration scalar
    
    return($fAppCalib);
};
# Final return value of one to indicate that the perl module is successful
1;