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
our @EXPORT = qw(setStartState OccupancySimulation);
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
    
    YEAR: for (my $i=1; $i<=365; $i++) { # for each day of the year
        # Determine which transition matrix to use
        my $tDay; 
        my @TRmat=();
        if ($dayWeek>7){$dayWeek=1};
        if ($dayWeek == 1 || $dayWeek == 7) {
            $tDay = 'we';
        } else { 
            $tDay = 'wd';
        };
        # Load appropriate transition matrix
        my $file = $dir . "/tpm" . "$numOcc" . "_" . $tDay . ".csv";
        open my $fh, '<', $file or die "Cannot open $file: $!";
        while (my $dat = <$fh>) {
            chomp $dat;
            push(@TRmat,$dat);
        };
        @TRmat = @TRmat[ 1 .. $#TRmat ]; # Trim out header
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
            TEN: while ($future<=$#data) {
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
        close $fh;
        print Dumper @Occ;
        sleep;
        $dayWeek++;
    }; # END YEAR 

    return (\@Occ);
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
    
    while (!$bOK) {
        $iGuess = (rand()*($dSD*8))-($dSD*4)+$dMean;
        my $px = (1/($dSD * sqrt(2*3.14159))) * exp(-(($iGuess - $dMean) ** 2) / (2 * $dSD * $dSD));

        if ($px >= rand()) {$bOK=1};

    };

    return $iGuess;
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