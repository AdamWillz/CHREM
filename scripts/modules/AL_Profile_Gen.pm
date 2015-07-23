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
our @EXPORT = qw(setStartState OccupancySimulation LightingSimulation GetIrradiance);
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
    
    my $WDfile = $dir . "/tpm" . "$numOcc" . "_wd.csv";
    open my $fh, '<', $WDfile or die "Cannot open $WDfile: $!";
    while (my $dat = <$fh>) {
        chomp $dat;
        push(@TRmatWD,$dat);
    };
    @TRmatWD = @TRmatWD[ 1 .. $#TRmatWD ]; # Trim out header
    close $fh;
    
    my $WEfile = $dir . "/tpm" . "$numOcc" . "_we.csv";
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
    my $iBulbs = scalar @fBulbs; # Number of bulbs/lamps in dwelling
    my $Tsteps = scalar @Occ;
    my $SMALL = 1.0e-20;
    
    # Declare output
    my @Light=(0) x $Tsteps;
    my $AnnPow;

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
                    $Light[$iTime] = $Light[$iTime]+$fBulbs[$i]; # [W]
                    
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
        $AnnPow=$AnnPow+(($Light[$k]*60)/1000); # [kJ]
        $Light[$k] = $Light[$k]/1000; # [kW]
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
    
    # Set local variables
    my @Irr_T=(); # Temporary array to hold irradiance file data
    
    # Declare output
    my @Irr=();
    
    open my $fh, '<', $file or die "Cannot open $file: $!";
    while (my $dat = <$fh>) {
        chomp $dat;
        push(@Irr_T,$dat);
    };
    @Irr_T = @Irr_T[ 2 .. ($#Irr_T-1) ]; # Trim out headers and last timestep 
    foreach my $data (@Irr_T) {
        my @temp = split /\t/, $data,2;
        push(@Irr, $temp[1]); 
    };

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

# Final return value of one to indicate that the perl module is successful
1;

# ====================================================================
# setColdProfile
#       This subroutine uses a top-down approach to generate high-resolution
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     region: location of fridge
#           size: size of the fridge/freezer [litres]
#           use: 'Primary' or 'Secondary'; primary or secondary fridge/freezer [string]
#           Tstep: Time step [min]
#           vint_dist: HASH holding fridge/ vintage distributions
#           cold_eff: HASH holding fridge/freezer annual energy consumption
# OUTPUT    ColdCyle: Annual electrical consumption profile of cold appliance [kW]
#
# REFERENCES: - NRCan, "Energy Consumption of Major Household Appliances Shipped in Canada:
#               Trends for 1990-2010", Office of Energy Efficiency, 2012.
#             - Widen, Wackelgard, "A high-resolution stochastic model of domestic activity
#               patterns and electricity demand". Applied Energy, 87, 2010.
#             
# ====================================================================

#sub setColdProfile {
#	# Read in inputs
#    my ($region, $size, $use, $Tstep, $vint_dist, $cold_eff) = @_;
#    if ($size <= 0) {die "Size '$size' of cold appliance invalid"};
#    
#    # Local variables
#    my $AnnE; # annual energy consumption [kWh/yr]
#    my $dist=$vint_dist->{$use}->{$region}; # generate HASH reference
#    my $TOn; # length of cycle where appliance is 'ON' [min]
#    my $TOff; # length of cycle where appliance is 'OFF' [min]
#    my $Ncyc; # Number of cycles per year [-]
#    my $Ecyc; # Energy consumption per cycle [kWh/cycle]
#    my $QOn; # Power draw when appliance is 'ON' [kW]
#    
#    # Convert size to cu. ft
#    $size = $size/28.316847;
#    
#    # Select vintage from distribution
#    my $i=1;
#    my $j=$dist->{"$i"}; # Initialize cumulative frequency
#    my $U = rand(); # Random number between 0 and 1
#    while ($j < $U && $i < $vint_dist->{'Periods'}->{'intervals'}) {
#        $i++;
#        $j=$j+$dist->{"$i"};
#    };
#
#    my $vintage = rand_range($vint_dist->{'Periods'}->{"$i"}->{'min'},$vint_dist->{'Periods'}->{"$i"}->{'max'});
#    
#    # Determine annual energy consumption
#    if ($vintage < $cold_eff->{'Eff'}->{'MinYear'}) {
#        $vintage = $cold_eff->{'Eff'}->{'MinYear'};
#    } elsif ($vintage > $cold_eff->{'Eff'}->{'MaxYear'}) {
#        $vintage = $cold_eff->{'Eff'}->{'MaxYear'};
#    };
#    
#    if ($vint_dist->{'Periods'}->{'type'} =~ m/fridge/) { # Fridge
#        if ($size > $cold_eff->{'Sizes'}->{$cold_eff->{'Sizes'}->{'intervals'}}->{'max'}) {
#            $size = $cold_eff->{'Sizes'}->{$cold_eff->{'Sizes'}->{'intervals'}}->{'max'};
#        };
#        $i = 1;
#        while ($cold_eff->{'Sizes'}->{"$i"}->{'max'} < $size) { # Find consumption data for appliance size
#            $i++;
#        };
#        
#        $AnnE = $cold_eff->{'Eff'}->{"$vintage"}->{"$i"};
#        
#    } elsif ($vint_dist->{'Periods'}->{'type'} =~ m/freezer/) { # Freezer
#        # Select a freezer type using distribution for particular vintage
#        $U = rand(100);
#        $j=0;
#        my $fType;
#        foreach my $type (keys (%{$cold_eff->{'types'}->{"$vintage"}})) {
#            $j=$j+$cold_eff->{'types'}->{"$vintage"}->{"$type"};
#            if ($j > $U) {
#                $fType = $type;
#                last;
#            };
#        };
#        
#        $AnnE = $cold_eff->{'Eff'}->{"$vintage"}->{"$fType"};
#    
#    } else { # Error
#        die "Invalid cold appliance type\n";
#    };
#
#    # Determine cycle lengths TOn and TOff
#    # TODO: find better values. For now, fridge cycle time from Armstrong et al. 2009
#    $TOn = 35;
#    $TOff = 35;
#    my $T = $TOn+$TOff; # Period of cycle [min]
#    
#    # Number of cycles per year
#    $Ncyc = 525600/$T;
#    # Energy consumption per cycle
#    $Ecyc = $AnnE/$Ncyc;
#    
#    # Power draw for appliance 'ON'
#    $QOn = $Ecyc/($TOn/60);
#    
#    # Generate Annual profile
#    my @ColdCyle = (0) x 525600; # Initialize output array
#    my $phase = int(rand($T-1)); # Randomly select offset of fridge cycle start
#    for (my $j=0; $j<=$#ColdCyle; $j++) {
#        # Determine state of appliance
#        if ($phase < $TOn) { # 'ON'
#            $ColdCyle[$j] = $QOn;
#        }; #else 'OFF'
#        $phase++;
#        if ($phase >= $T) {$phase=0}; # period complete
#    
#    };
#    
#    # Adjust profile to user requested timestep
#    if ($Tstep != 1) {
#        my $chkSize = 525600/$Tstep; # Determine number of timesteps per year
#        my @Adj=();
#        my $n=0; # Index old array
#        for (my $j=0; $j <= ($chkSize-1); $j++) {
#            my $E=0; # Variable to store energy consumed over $Tstep [kW min]
#            for (my $k=1; $k<=$Tstep; $k++) {
#                $E = $E + $ColdCyle[$n];
#                $n++;
#            };
#            push(@Adj, ($E/$Tstep));
#        };
#        @ColdCyle = @Adj; # Update profile
#    };
#    
#    return (\@ColdCyle);
#    
#};