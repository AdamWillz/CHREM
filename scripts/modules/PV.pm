# ====================================================================
# PV.pm
# Author: Adam Wills
# Date: Feb 2015
# Copyright: Carleton University
# ====================================================================
# The following subroutines are included in the perl module:
# rm_EOL_and_trim: a subroutine that removes all end of line characters (DOS, UNIX, MAC) and trims leading/trailing whitespace
# hse_types_and_regions_and_set_name: a subroutine that reads in user input and stores returns the house type and region and set name information
# header_line: a subroutine that reads a file and returns the header as an array within a hash reference 'header'
# one_data_line: a subroutine that reads a file and returns a line of data in the form of a hash ref with header field keys
# one_data_line_keyed: similar but stores everything at a hash key (e.g. $data->{'data'} = ...
# largest and smallest: simple subroutine to determine and return the largest or smallest value of a passed list
# check_range: checks value against min/max and corrects if require with a notice
# set_issue: simply pushes the issue into the issues hash reference in a formatted method
# print_issues: subroutine prints out the issues encountered by the script during execution
# distribution_array: returns an array of values distributed in accordance with a hash to a defined number of elements
# die_msg: reports a message and dies
# replace: reads through an array and replaces a matching line with new information
# insert: reads through an array and inserts a matching line with new information
# ====================================================================

# Declare the package name of this perl module
package PV;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Data::Dumper;
use Math::Trig;
use Math::Polygon::Calc;

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw( surf_slope_azimuth rotate_vector poly_obj R3_cross R_dot tri_trap_rect rect_finite_first_fit trap_finite_first_fit tri_finite_first_fit set_origin);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# surf_slope_azimuth
# INPUT     RotAng: Angle of rotation (CCW about the z-axis) [deg]
#           P1: Array holding x,y,z coordinates of point 1 on plane
#           P2: Array holding x,y,z coordinates of point 2 on plane
#           P3: Array holding x,y,z coordinates of point 3 on plane
# OUTPUT    Slope: slope angle of plane [deg]
#           Azimuth: Measured CW from north (y-axis) [deg]
#           n: Normalized normal vector, untransformed (x,y,z)
#
# ====================================================================

sub surf_slope_azimuth {
	# Read in inputs
    my ($RotAng, $P1, $P2, $P3) = @_;
    
    # Declare local variables
    my @P12=();
    my @P13=();
    my @n=();   # Untransformed normal vector
    my @Nn = ();# Transformed normal vector
    
    # Generate two vectors on the plane
    for (my $i=0; $i <=2; $i++) {
        push(@P12, (${$P2}[$i] - ${$P1}[$i]));
        push(@P13, (${$P3}[$i] - ${$P1}[$i]));
    };
    
    # Determine the normal vector to the plane
    my $coord = ($P12[1]*$P13[2])-($P12[2]*$P13[1]);
    push(@n, $coord );
    $coord = ($P12[2]*$P13[0])-($P12[0]*$P13[2]);
    push(@n, $coord );
    $coord = ($P12[0]*$P13[1])-($P12[1]*$P13[0]);
    push(@n, $coord );
    # print Dumper @n;
    
    # If the z-coordinate of the array is negative, reverse direction
    if ($n[2] < 0) {
        for (my $i=0; $i <=2; $i++) {
            $n[$i] = $n[$i]*(-1);
        };
    };

    if ($RotAng == 0) { # No need to perform transform
        @Nn = @n;
    } else { # Rotate the normal vector CCW about the z-axis
        my $Nn_ref = rotate_vector(\@n, $RotAng);
        @Nn = @$Nn_ref;
    };

    # Determine the azimuth (clockwise from north)
    my $nMag = sqrt(($Nn[0]**2) + ($Nn[1]**2)); # Magnitude of the normal vector projected to xy plane
    my $Azimuth = acos($Nn[1]/$nMag);
    $Azimuth = rad2deg($Azimuth);
    if ($Nn[0] < 0 ) { # Third or fourth quadrant, adjust angle
        $Azimuth = 360 - $Azimuth;
    };

    
    # Determine the slope angle
    $nMag = sqrt(($Nn[0]**2) + ($Nn[1]**2)); # Magnitude of the normal vector projected to xz plane
    my $VMag = abs(sqrt(($Nn[0]**2) + ($Nn[1]**2) + ($Nn[2]**2))); # Magnitude of the normal, assuming positive z-component
    my $Slope = acos($nMag/$VMag);
    $Slope = 90-rad2deg($Slope);
    
    $nMag = sqrt(($n[0]**2) + ($n[1]**2) + ($n[2]**2));
    for (my $i=0; $i <=2; $i++) {
        $n[$i] = $n[$i]/$nMag;
    };

    return ($Slope,$Azimuth,\@n);

};

# ====================================================================
# rotate_vector
# INPUT     n: Vector to be rotated (x,y,z)
#           ang: Angle of rotation (CCW about the z-axis) [deg]
# OUTPUT    Nn: Rotated vector (x,y,z)
#
# ====================================================================

sub rotate_vector {

    my ($n, $ang) = @_;
    my $SMALL = 1.0e-10;
    
    my @Nn = ();# Transformed normal vector
    my $rad = deg2rad($ang);
    my $coord = (${$n}[0]*cos($rad))-(${$n}[1]*sin($rad));
    if (abs($coord) < $SMALL) {$coord=0.0};
    push(@Nn, $coord );
    $coord = (${$n}[0]*sin($rad))+(${$n}[1]*cos($rad));
    if (abs($coord) < $SMALL) {$coord=0.0};
    push(@Nn, $coord );
    push(@Nn, ${$n}[2] );
    
    return (\@Nn);
};

# ====================================================================
# poly_obj
# INPUT     P: Array of ordered coordinates for each vertex of surface, 
#              [x1, y1, z1, x2, y2, z2, ..., xn, yn, zn]
#           n: normal vector, [x, y, z]
#           numVert: number of vertices 
#
# ====================================================================

sub poly_obj {
    my ($P_ref, $n_ref, $numVert) = @_;
    my @P = @$P_ref;
    my @n = @$n_ref;
    
    # Normalize the normal vector
    my $Mag = sqrt(($n[0]**2)+($n[1]**2)+($n[2]**2));
    my @Nn = (); # Array to hold normalized vector
    for (my $i=0; $i <= 2; $i++) {
        push(@Nn, ($n[$i]/$Mag));
    };
    
    # Develop new orthogonal coordinate system to move surface to R2 space
    my @Xnorm = (1,0,0);
    my $Y_ref = R3_cross(\@Nn, \@Xnorm);
    my @Y = @$Y_ref;
    my $Mag = sqrt(($Y[0]**2)+($Y[1]**2)+($Y[2]**2));
    for (my $i=0; $i <= 2; $i++) { # Normalize vector
        $Y[$i] = $Y[$i]/$Mag;
    };
    
    my @Ynorm = (0,1,0);
    my $X_ref = R3_cross(\@Nn, \@Ynorm);
    my @X = @$X_ref;
    my $Mag = sqrt(($X[0]**2)+($X[1]**2)+($X[2]**2));
    for (my $i=0; $i <= 2; $i++) { # Normalize vector
        $X[$i] = $X[$i]/$Mag;
    };
    
    # Selecting first vertex of surface as origin, determine new xy coordinates of surface
    my @Pnew = ([0,0]);
    my @VertInd = (); # Array to index vertices in array P
    for (my $i = 1; $i < $numVert; $i++) {
        push(@VertInd, ($i*3));
    };
    foreach my $j (@VertInd) {
        my @temp = ();
        push(@temp, ($P[$j] - $P[0]));
        push(@temp, ($P[$j+1] - $P[1]));
        push(@temp, ($P[$j+2] - $P[2]));
        
        push(@Pnew, [R_dot(\@temp, \@X), R_dot(\@temp, \@Y)]);
    };
    push(@Pnew,[0,0]); # Close the polygon
    
    my ($type, $L_refs) = tri_trap_rect(\@Pnew);
    my @lengths = @$L_refs;
    
    my $poly = Math::Polygon->new( @Pnew );

    return ($poly,$type,\@lengths);

};

# ====================================================================
# R3_cross
# INPUT     A: Vector in R3
#           B: Vector in R3
# OUTPUT    C: Result of A cross B
#
# ====================================================================

sub R3_cross {

    my ($A_ref, $B_ref) = @_;
    my @A = @$A_ref;
    my @B = @$B_ref;
    my @C = ();
    
    push(@C, ($A[1]*$B[2])-($A[2]*$B[1]));
    push(@C, ($A[2]*$B[0])-($A[0]*$B[2]));
    push(@C, ($A[0]*$B[1])-($A[1]*$B[0]));
    
    return (\@C);

};

# ====================================================================
# R_dot
# INPUT     A: Vector in Rn
#           B: Vector in Rn
# OUTPUT    C: Result of A dot B
#
# ====================================================================

sub R_dot {

    my ($A_ref, $B_ref) = @_;
    my @A = @$A_ref;
    my @B = @$B_ref;
    my $Dot=0;
    
    for (my $i=0; $i <= $#A; $i++) {
        $Dot = $Dot+($A[$i]*$B[$i]);
    };
    
    return ($Dot);

};

# ====================================================================
# tri_trap_rect
# INPUT     poly: polygon object
#
# OUTPUT    type: String; 'rect', 'tri', 'trap', or 'unknown'
#
# ====================================================================

sub tri_trap_rect {

    my @points = @{$_[0]};
    my $type;
    my @Lengths = ();
    my $size = $#points; # Number of points that define the surface
    
    if ($size == 3) {
        $type = 'tri';
        for (my $i=0; $i <3; $i++) {
            push(@Lengths, sprintf("%.3f", polygon_perimeter ($points[$i],$points[$i+1])));
        };
    } elsif ($size == 4) { # rectangle or trapezoid
        for (my $i=0; $i <4; $i++) {
            push(@Lengths, sprintf("%.3f", polygon_perimeter ($points[$i],$points[$i+1])));
        };

        if ($Lengths[0] == $Lengths[2] && $Lengths[1] == $Lengths[3]) {
            $type = 'rect';
        } else {
            $type = 'trap';
        };
    } elsif ($size < 3) {
        die "The number of points defining this surface is less than 3, not possible! \n";
    } else {
        $type = 'unknown';
    };

    return ($type,\@Lengths);

};

# ====================================================================
# rect_finite_first_fit
# INPUT     DIM: array; element 1 is length and element 2 width of bin
#           PL: length of piece to be packed in the bin
#           PW: width of piece to be packed in the bin
#
# OUTPUT    Num_P: Number of pieces that fit in the bin
#
# ====================================================================

sub rect_finite_first_fit {
    my ($DIM_ref, $PL, $PW) = @_;
    my @DIM = @$DIM_ref;
    my @PR = ($PL, $PW); # Array to hold length and width of pieces
    my $BL = $DIM[0]; # Bin length
    my $BH = $DIM[1]; # Bin height

    my $Num_P = 0; # Integer to hold the number of pieces that can fit in the bin
    

    my @iA = (1,0); # Indexers to randomly set orientation of the panels
    my @iB = (0,1);
    
    
    for (my $i=0; $i <= 1; $i++) { # Try 2 different orientations of pieces
        # Determine orientation of piece
        my $L = $PR[$iA[$i]];
        my $H = $PR[$iB[$i]];
        # Initialize values
        my $TopH = $H;      # Height of the top of the current level
        my $LL = $BL;       # Available space on current level
        my $BaseH = 0;      # Height of the base of the current level
        my $count = 0;      # Generic counter
        my $BinFull = 0;    # Flag to indicate bin is full
        
        while ($BinFull != 1) { # While the bin isn't full, place a piece
            # Update space left on level
            $LL = $LL - $L;
            if ($LL < 0) {  # Level full, move up to next level
                $BaseH = $TopH;
                $TopH = $BaseH+$H;
                $LL=$BL-$L;
                if ($LL < 0) {$BinFull = 1};  # This piece has a lenght bigger than bin, close
            };
            
            # Check there is available height for piece
            if (($BaseH+$H) > $BH) {# Piece goes through top of rectangle, close
                $BinFull = 1
            } elsif (($BaseH+$H) > $TopH) {
                $TopH = $BaseH+$H;
            };
            
            if ($BinFull != 1) { # Piece fits, place it
                $count = $count+1;
            };
        };
        # UPDATE VARIABLES AFTER BIN PACKED
        if ($count > $Num_P) {
            $Num_P = $count;
        };
    };
    return ($Num_P);
};

# ====================================================================
# trap_finite_first_fit
# INPUT     DIM: array; element 1 is length and element 2 width of bin
#           PL: length of piece to be packed in the bin
#           PW: width of piece to be packed in the bin
#
# OUTPUT    Num_P: Number of pieces that fit in the bin
#
# ====================================================================

sub trap_finite_first_fit {
    my ($DIM_ref, $PL, $PW) = @_;
    my @DIM = @$DIM_ref;
    my @PR = ($PL, $PW); # Array to hold length and width of pieces
    
    # Determine trapezoid dimension
    my $sides;
    my $base;
    my $top;
    my @BT=();
    SIDES: {
    foreach my $x (@DIM) {
        foreach my $y (@DIM) {
            if ($x == $y) {
                $sides = $x;
                foreach my $z (@DIM) {
                    if ($z != $sides) {push(@BT,$z)};
                };
                if ($#BT < 1) { # Only one element in array, 3 sides are equal
                    $base = $sides;
                    $top = $BT[0];
                } elsif ($BT[0] > $BT[1]) {
                    $base = $BT[0];
                    $top = $BT[1];
                } else {
                    $base = $BT[1];
                    $top = $BT[0];
                };
                last SIDES;
            };
        };
    };
    };
    my $BH = sqrt(($sides**2)-((($base-$top)/2)**2)); # Bin height
    my $theta = asin($BH/$sides);

    my $Num_P = 0; # Integer to hold the number of pieces that can fit in the bin
   
    my @iA = (1,0); # Indexers to randomly set orientation of the panels
    my @iB = (0,1);
    
    
    for (my $i=0; $i <= 1; $i++) { # Try 2 different orientations of pieces
        # Determine orientation of piece
        my $L = $PR[$iA[$i]];
        my $H = $PR[$iB[$i]];
        my $trim = 2*($H/tan($theta));
        
        # Initialize variables
        my $BL = $base - $trim; # Initialize available level space
        my $LL = $BL;       # Initialize remaining space on level
        my $TopH = $H;      # Height of the top of the current level
        my $BaseH = 0;      # Height of the base of the current level
        my $BinFull = 0;    # Flag to indicate bin is full
        my $count = 0;      # Generic counter

        while ($BinFull != 1) { # While the bin isn't full, place a piece
            # Update space left on level
            $LL = $LL - $L;
            if ($LL < 0) {  # Level full, move up to next level
                $BaseH = $TopH;
                $TopH = $BaseH+$H;
                $BL = $BL - $trim;
                $LL=$BL-$L;
                if ($LL < 0 || $BL < 0) {$BinFull = 1};  # This piece has a length bigger than bin, close
            };
            
            # Check there is available height for piece
            if (($BaseH+$H) > $BH) {# Piece goes through top of rectangle, close
                $BinFull = 1;
            };
            
            if ($BinFull != 1) { # Piece fits, place it
                $count = $count+1;
            };
        };
        # UPDATE VARIABLES AFTER BIN PACKED
        if ($count > $Num_P) {
            $Num_P = $count;
        };
    };
    return ($Num_P);
};

# ====================================================================
# tri_finite_first_fit
# INPUT     DIM: array; element 1 is length and element 2 width of bin
#           PL: length of piece to be packed in the bin
#           PW: width of piece to be packed in the bin
#
# OUTPUT    Num_P: Number of pieces that fit in the bin
#
# ====================================================================

sub tri_finite_first_fit {
    my ($DIM_ref, $PL, $PW) = @_;
    my @DIM = @$DIM_ref;
    my @PR = ($PL, $PW); # Array to hold length and width of pieces
    
    # Determine trapezoid dimension
    my $sides;
    my $base;
    my @BT=();
    SIDES: {
    foreach my $x (@DIM) {
        foreach my $y (@DIM) {
            if ($x == $y) {
                $sides = $x;
                foreach my $z (@DIM) {
                    if ($z != $sides) {
                        $base=$z
                    };
                };
                if  (! defined $base) { # All side are equal
                    $base = $sides;
                };
                last SIDES;
            };
        };
    };
    };
    my $BH = sqrt(($sides**2)-(($base/2)**2)); # Bin height
    my $theta = asin($BH/$sides);
    
   
    my $Num_P = 0; # Integer to hold the number of pieces that can fit in the bin
   

    my @iA = (1,0); # Indexers to randomly set orientation of the panels
    my @iB = (0,1);
    
    
    for (my $i=0; $i <= 1; $i++) { # Try 2 different orientations of pieces
        # Determine orientation of piece
        my $L = $PR[$iA[$i]];
        my $H = $PR[$iB[$i]];
        my $trim = 2*($H/tan($theta));
        
        # Initialize variables
        my $BL = $base - $trim; # Initialize available level space
        my $LL = $BL;       # Initialize remaining space on level
        my $TopH = $H;      # Height of the top of the current level
        my $BaseH = 0;      # Height of the base of the current level
        my $BinFull = 0;    # Flag to indicate bin is full
        my $count = 0;      # Generic counter

        while ($BinFull != 1) { # While the bin isn't full, place a piece
            # Update space left on level
            $LL = $LL - $L;
            if ($LL < 0) {  # Level full, move up to next level
                $BaseH = $TopH;
                $TopH = $BaseH+$H;
                $BL = $BL - $trim;
                $LL=$BL-$L;
                if ($LL < 0 || $BL < 0) {$BinFull = 1};  # This piece has a length bigger than bin, close
            };
            
            # Check there is available height for piece
            if (($BaseH+$H) > $BH) {# Piece goes through top of rectangle, close
                $BinFull = 1;
            };
            
            if ($BinFull != 1) { # Piece fits, place it
                $count = $count+1;
            };
        };
        # UPDATE VARIABLES AFTER BIN PACKED
        if ($count > $Num_P) {
            $Num_P = $count;
        };
    };
    return ($Num_P);
};

# Final return value of one to indicate that the perl module is successful
1;
