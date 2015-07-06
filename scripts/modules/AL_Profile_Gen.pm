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
use Data::Dumper;
use POSIX qw(ceil floor);

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
#our @EXPORT = qw( setDryerProfile setStoveProfile setOtherProfile setNewBCD);
our @EXPORT = qw(setColdProfile);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

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

sub setColdProfile {
	# Read in inputs
    my ($region, $size, $use, $Tstep, $vint_dist, $cold_eff) = @_;
    if ($size <= 0) {die "Size '$size' of cold appliance invalid"};
    
    # Local variables
    my $AnnE; # annual energy consumption [kWh/yr]
    my $dist=$vint_dist->{$use}->{$region}; # generate HASH reference
    my $TOn; # length of cycle where appliance is 'ON' [min]
    my $TOff; # length of cycle where appliance is 'OFF' [min]
    my $Ncyc; # Number of cycles per year [-]
    my $Ecyc; # Energy consumption per cycle [kWh/cycle]
    my $QOn; # Power draw when appliance is 'ON' [kW]
    
    # Convert size to cu. ft
    $size = $size/28.316847;
    
    # Select vintage from distribution
    my $i=1;
    my $j=$dist->{"$i"}; # Initialize cumulative frequency
    my $U = rand(); # Random number between 0 and 1
    while ($j < $U && $i < $vint_dist->{'Periods'}->{'intervals'}) {
        $i++;
        $j=$j+$dist->{"$i"};
    };

    my $vintage = rand_range($vint_dist->{'Periods'}->{"$i"}->{'min'},$vint_dist->{'Periods'}->{"$i"}->{'max'});
    
    # Determine annual energy consumption
    if ($vintage < $cold_eff->{'Eff'}->{'MinYear'}) {
        $vintage = $cold_eff->{'Eff'}->{'MinYear'};
    } elsif ($vintage > $cold_eff->{'Eff'}->{'MaxYear'}) {
        $vintage = $cold_eff->{'Eff'}->{'MaxYear'};
    };
    
    if ($vint_dist->{'Periods'}->{'type'} =~ m/fridge/) { # Fridge
        if ($size > $cold_eff->{'Sizes'}->{$cold_eff->{'Sizes'}->{'intervals'}}->{'max'}) {
            $size = $cold_eff->{'Sizes'}->{$cold_eff->{'Sizes'}->{'intervals'}}->{'max'};
        };
        $i = 1;
        while ($cold_eff->{'Sizes'}->{"$i"}->{'max'} < $size) { # Find consumption data for appliance size
            $i++;
        };
        
        $AnnE = $cold_eff->{'Eff'}->{"$vintage"}->{"$i"};
        
    } elsif ($vint_dist->{'Periods'}->{'type'} =~ m/freezer/) { # Freezer
        # Select a freezer type using distribution for particular vintage
        $U = rand(100);
        $j=0;
        my $fType;
        foreach my $type (keys (%{$cold_eff->{'types'}->{"$vintage"}})) {
            $j=$j+$cold_eff->{'types'}->{"$vintage"}->{"$type"};
            if ($j > $U) {
                $fType = $type;
                last;
            };
        };
        
        $AnnE = $cold_eff->{'Eff'}->{"$vintage"}->{"$fType"};
    
    } else { # Error
        die "Invalid cold appliance type\n";
    };

    # Determine cycle lengths TOn and TOff
    # TODO: find better values. For now, fridge cycle time from Armstrong et al. 2009
    $TOn = 35;
    $TOff = 35;
    my $T = $TOn+$TOff; # Period of cycle [min]
    
    # Number of cycles per year
    $Ncyc = 525600/$T;
    # Energy consumption per cycle
    $Ecyc = $AnnE/$Ncyc;
    
    # Power draw for appliance 'ON'
    $QOn = $Ecyc/($TOn/60);
    
    # Generate Annual profile
    my @ColdCyle = (0) x 525600; # Initialize output array
    my $phase = int(rand($T-1)); # Randomly select offset of fridge cycle start
    for (my $j=0; $j<=$#ColdCyle; $j++) {
        # Determine state of appliance
        if ($phase < $TOn) { # 'ON'
            $ColdCyle[$j] = $QOn;
        }; #else 'OFF'
        $phase++;
        if ($phase >= $T) {$phase=0}; # period complete
    
    };
    
    # Adjust profile to user requested timestep
    if ($Tstep != 1) {
        my $chkSize = 525600/$Tstep; # Determine number of timesteps per year
        my @Adj=();
        my $n=0; # Index old array
        for (my $j=0; $j <= ($chkSize-1); $j++) {
            my $E=0; # Variable to store energy consumed over $Tstep [kW min]
            for (my $k=1; $k<=$Tstep; $k++) {
                $E = $E + $ColdCyle[$n];
                $n++;
            };
            push(@Adj, ($E/$Tstep));
        };
        @ColdCyle = @Adj; # Update profile
    };
    
    return (\@ColdCyle);
    
};

# ====================================================================
# setDryerProfile
# INPUT     emp_ratio: employment ratio
#           cycles: Cycles per week
#           Tstep: time step [min]
# OUTPUT    DryerProfile: slope angle of plane [deg]
#           Azimuth: Measured CW from north (y-axis) [deg]
#           n: Normalized normal vector, untransformed (x,y,z)
#
# ====================================================================

#sub setDryerProfile {
#	# Read in inputs
#    my ($emp_ratio, $cycles, $Tstep) = @_;
#    
#    # Declare local variables
#    my $ProPath = '../bcd/Stochastic/Dryer/';
#    my $AnnCycl = ceil($cycles*52); # Annual number of dryer cycles
#    my $src; # Which recorded house to use as a template
#    my $Nstep = 525600/$Tstep; # Number of timeteps per year
#    my @PDF = (); # Array to hold the annual pdf
#    my @Prof = (); # Array to hold the cycle data
#    
#    # Error handling
#    if (525600 % $Tstep) {
#        die "In setDryerProfile: Timestep request $Tstep invalid";
#    };
#    
#    # Determine which house template to use
#    if ($emp_ratio == 1) { # All adults work, no laundry during the day
#        $src = 'H10';
#    } elsif ($cycles <= 1.8) { # Use data from H15
#        $src = 'H15';
#    } elsif ($cycles <= 3) { # Use data from H14
#        $src = 'H14';
#    } elsif ($cycles <= 4.5) { # Use data from H13
#        $src = 'H13';
#    } else { # Use data from H12
#        $src = 'H12';
#    };
#    
#    # Read in p.d.f. for dryer usage
#    my $filename = $ProPath . $src . '_Dryer.csv';
#    open(my $fh, '<:encoding(UTF-8)', $filename) or die "Could not open file '$filename' $!";
#    
#    while (my $row = <$fh>) {
#        chomp $row;
#        push(@PDF, $row);
#    };
#    close $fh;
#    
#    # Error handling
#    my $chkSize = @PDF;
#    if ($chkSize != 525600) {die "Input file '$filename' has incorrect number of elements"};
#    
#    # Determine when "ON" events occur
#    my @OnTime = (0) x $chkSize; # Initialize array to hold when "ON" events occur
#    my $iCycle = 0;
#    while ($iCycle <= $AnnCycl) {
#        my $i = int(rand($#PDF)); # Randomly select time from PDF
#        if ($PDF[$i] > 0) { # There is a chance the dryer will turn on
#            my $ON = rand(); # Randomly select a number between 0 and 1
#            if ($ON >= $PDF[$i]) { # Set to "ON" event
#                $OnTime[$i] = 1;
#                $iCycle++;
#            };
#        };
#    };
#    
#    # Read in single-cycle profile
#    $filename = $ProPath . 'Cycle/' . $src . '_Dryer_Profile.csv';
#    open(my $fh, '<:encoding(UTF-8)', $filename) or die "Could not open file '$filename' $!";
#    while (my $row = <$fh>) {
#        chomp $row;
#        push(@Prof, $row);
#    };
#    close $fh;
#    
#    # Generate annual dryer usage profile 
#    my $i = 0;
#    my @Dryer = (0) x $chkSize;
#    foreach my $item (@OnTime) {
#        if ($item > 0) { # Dryer is turned on
#            if ($Dryer[$i] <= 0 && $Dryer[$i+$#Prof+1] <= 0) {
#                my $j=$i;
#                foreach my $data (@Prof) {
#                    $Dryer[$j] = $Dryer[$j] + $data;
#                    $j++;
#                };
#            } else {
#                die "Dryer events overlapping: Terminating\n";
#            };
#        };
#        $i++;
#    };
#    
#    return (\@Out, \@OnTime);
#
#};

# ====================================================================
#  LOCAL SUBROUTINES
# ====================================================================

sub rand_range {
    my ($x, $y) = @_;
    return int(rand($y - $x)) + $x;
};

# Final return value of one to indicate that the perl module is successful
1;
