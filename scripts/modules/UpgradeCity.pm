# ====================================================================
# AL_Profile_Gen.pm
# Author: Adam Wills
# Date: June 2016
# Copyright: Carleton University
# ====================================================================
# The following subroutines are included in the perl module:
# ====================================================================

# Declare the package name of this perl module
package UpgradeCity;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Cwd;
use Data::Dumper;

use lib qw(./modules);
use PV;

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(getGEOdata upgradeCeilIns setBCDpath upgradeBsmtIns);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# getGEOdata
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getGEOdata {
    # get list of dwellings
    my ($list_ref, $path) = @_;
    my @list = @$list_ref;
    
    # Outputs
    my $Surf;
    
    # Intermediates
    
    
    Go_list: foreach my $rec (@list) { # For each record
        # Get the paths for all the geo files in this model
        my $recPath = $path . "$rec";
        my @geofiles = glob "$recPath/*.geo";
        my $VertsList;
        
        # Determine the zone ordering
        $Surf = getZoneDataCFG($rec,$path,$Surf);

        # Load each geo file
        foreach my $zone (@geofiles) {
            my $iSurfNum=1;
            my $RelPath = $zone;
            # Determine the zone name
            $zone =~ s/\.geo$//;
            $zone =~ s/.*\.//;
            my @ZoneAreas=(); # Array to hold the zone surface areas [m2]
            my @SufNames=();
            
            # Crack open the geo file 
            my $GeoFID;
            open $GeoFID, $RelPath or die "Could not open $RelPath\n";
            my @lines = <$GeoFID>; # Pull entire file into an array
            
            # Load in the vertices
            my $DataLine=0;
            my $FileLine=0;
            until (($lines[$FileLine] !~ m/^(#)/i) && ($DataLine>2)) {
                $FileLine++;
                if($lines[$FileLine] !~ m/^(#)/i){$DataLine++};
            };
            my $nVerts=1; # Number of vertices in this zone
            until($lines[$FileLine] =~ m/^(#)/i) {
                my $thisVert = "v$nVerts";
                $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                my @LineDat = split ' ', $lines[$FileLine];
                $VertsList->{$thisVert}->{'x'} = $LineDat[0];
                $VertsList->{$thisVert}->{'y'} = $LineDat[1];
                $VertsList->{$thisVert}->{'z'} = $LineDat[2];
                $nVerts++;
                $FileLine++;
            };
            $nVerts--;

            # Begin looping through surface data
            #====================================================================
            until($lines[$FileLine] =~ m/^(#END_SURFACES)/) {
                my @VertSurflist=(); # Array holding all the vertices in order
                if($lines[$FileLine] =~ m/^(#)/i) {
                    $FileLine++;
                } else {
                    my @AoA=(); # Array of array holding the coordinate data for the surface
                    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                    my @LineDat = split /[,\s]+/, $lines[$FileLine];
                    my $surfVerts = shift @LineDat; # Number of vertices defining this surface

                    for (my $i=0;$i<$surfVerts;$i++) { # Get the vertex listing
                        push(@VertSurflist,$LineDat[$i]);
                    };

                    # Populate AoA with the coordinates of each vertex of the surface
                    foreach my $point (@VertSurflist) {
                        my @thisCoord=();
                        push(@thisCoord,$VertsList->{"v$point"}->{'x'});
                        push(@thisCoord,$VertsList->{"v$point"}->{'y'});
                        push(@thisCoord,$VertsList->{"v$point"}->{'z'});
                        push @AoA, [@thisCoord];
                    };
                    my $thisArea = &area3D_Polygon(\@AoA);
                    
                    push(@ZoneAreas, $thisArea);
                    $FileLine++;
                };
            }; # End of surface-vertex data
            
            # Get the surface attributes
            until($lines[$FileLine] =~ m/^(#SURFACE_ATTRIBUTES)/) {$FileLine++;} # FFWD to surface attributes
            until($lines[$FileLine] !~ m/^(#)/i) {$FileLine++;} # Skip past any preliminary comments
            until($lines[$FileLine] =~ m/^(#)/i) { # Read in the surface attributes
                $lines[$FileLine] =~ s/^\s+|\s+$//g; # Trim leading and lagging whitespace
                my @LineDat = split /[,\s]+/, $lines[$FileLine];
                $Surf->{"_$rec"}->{$zone}->{'Surfaces'}->{"$LineDat[1]"}->{'area'} = shift(@ZoneAreas);
                $Surf->{"_$rec"}->{$zone}->{'Surfaces'}->{"$LineDat[1]"}->{'surf_num'} = $iSurfNum;
                
                $iSurfNum++;
                $FileLine++;
            };

        };
        
        # Get the links 
        $Surf->{"_$rec"} = getCNN($rec,$path,$Surf->{"_$rec"});

    }; # End of record
    
    return $Surf;
};
# ====================================================================
# upgradeCeilIns
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeCeilIns {
    # Inputs
    # Name of dwelling, Maximum ceiling insulation (RSI), path to the set, HASH holding upgrade data
    my ($house_name,$UpgradesCeil,$thisHouse,$setPath,$UPGrecords) = @_;
    
    # Intermediates
    my $strRoofType; # String holding the roof type (attic|flat)
    my $strAdj;     # Name of the zone adjacent to the attic
    
    # Determine the roof type
    foreach my $zones (keys (%{$thisHouse})) {
        if ($zones =~ m/attic/) {
            $strRoofType=$zones;
            last;
        };
        if ($zones =~ m/roof/) {
            $strRoofType=$zones;
            last;
        };
    };
    if (not defined($strRoofType)) {die"$house_name: Could not find attic or roof\n";}
    
    if ($strRoofType =~ m/attic/) {
        # Gather and update the attic construction data
        my $recPath = $setPath . "$house_name/";
        
        $UPGrecords = UpdateCONdataCEILING($UpgradesCeil,$house_name,$recPath,$thisHouse,$strRoofType,'floor',$UPGrecords);
        
        # Update the upgrade record

    } else { # This is a flat roof
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"roof"}->{"floor"}->{'new_RSI'} = 0.0;
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"roof"}->{"floor"}->{'original_RSI'} = 0.0;
    };
    
    return $UPGrecords;

}; # END upgradeCeilIns
# ====================================================================
# setBCDpath
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setBCDpath {
    my ($ref_hse,$BCDPath,$setPath) = @_;
    my @houses_desired = @$ref_hse;
    
    ECH_HSE: foreach my $hse (@houses_desired) {
        # Load the cfg
        my $ThisCFGpath = $setPath . "$hse/$hse.cfg";
        my $CfgFID;
        open $CfgFID, $ThisCFGpath or die "Could not open $ThisCFGpath\n";
        my @lines = <$CfgFID>; # Pull entire file into an array
        close $CfgFID;
        
        # Update the bcd entry
        my $FileLine = 0;
        until (($lines[$FileLine] =~ /^(\*bcd)/) || ($FileLine==$#lines)) {$FileLine++};
        $lines[$FileLine] = "*bcd ../../$BCDPath/$hse.bcd\n";
        
        # Write the new cfg file
        open my $out, '>', $ThisCFGpath or die "Can't write $ThisCFGpath: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;
    
    }; # END ECH_HSE
};
# ====================================================================
# upgradeBsmtIns
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeBsmtIns {
    # Inputs
    # Name of dwelling, Maximum basement insulation (RSI), path to the set, HASH holding upgrade data
    my ($house_name,$UpgradesBsmt,$thisHouse,$setPath,$UPGrecords) = @_;
    
    # Intermediates
    my $strFdnType; # String holding the foundation type
    my $recPath = $setPath . "$house_name/";
    
    # Determine the foundation type
    foreach my $zones (keys (%{$thisHouse})) {
        if ($zones =~ m/bsmt/) {
            $strFdnType=$zones;
            last;
        };
        if ($zones =~ m/crawl/) {
            $strFdnType=$zones;
            last;
        };
    };
    if (not defined($strFdnType)) {$strFdnType="slab";}
    
    # Determine what kind of BASESIMP configuration is being used
    my $BsmtIndex = getBSMTType($house_name,$recPath);
        
    # Only apply insulation to foundation type `bsmt'
    if($strFdnType =~ m/bsmt/) {
        $UPGrecords = setBSMfile($house_name,$recPath,$BsmtIndex,$UpgradesBsmt,$UPGrecords);
        
    } else { # Foundation is slab or crawlspace
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'foundation_type'} = $strFdnType;
    }; 

    return $UPGrecords;

}; # END upgradeCeilIns

# ====================================================================
# *********** PRIVATE METHODS ***************
# ====================================================================
# UpdateCONdata
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub UpdateCONdataCEILING{
    my ($UpgradesSurf,$house_name,$recPath,$thisHouse,$zone,$surfname,$UPGrecords) = @_;
    
    # Intermediates
    my $IndexLayerGaps; # Holds the line index in con file for number of layers and gaps
    my $iMatLayrs;
    #my $iGaps;
    my $surfNum = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'surf_num'};
    #my @GapsData; # Array to hold the air gap data
    my @LayerCon;
    my @LayerThick;
    my @NewCons;
    my $conPath = $recPath . "$house_name" . ".$zone" . ".con";
    my $strNewLayer; # String to hold the new layer data
    
    # Outputs
    my $OrigRSI=0;
    my $NewRSI;
    
    # Load this zone's construction file
    my $ConFID;
    open $ConFID, $conPath or die "Could not open $conPath\n";
    my @lines = <$ConFID>; # Pull entire file into an array
    close $ConFID;
    
    # Find the number of layers and gaps for surface
    my $DataLine=0;
    my $FileLine=0;
    until (($lines[$FileLine] !~ m/^(#)/i) && ($DataLine==$surfNum)) {
        $FileLine++;
        if($lines[$FileLine] !~ m/^(#)/i){$DataLine++};
    };
    $IndexLayerGaps = $FileLine; # Store index to surface number of layers and gaps
    my $ThisLine=$lines[$FileLine]; 
    $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split /[,\s]+/, $ThisLine;
    $iMatLayrs = $LineDat[0];
    #$iGaps = $LineDat[1];

    # If there are air gaps, get the data
    #if($iGaps>0) { 
    #    $DataLine = 0;
    #    until ($lines[$FileLine] =~ m/^(#GAP_POS_AND_RSI)/i) {
    #        $FileLine++;
    #    };
    #    while ($DataLine < $surfNum) {
    #        $DataLine++;
    #        $FileLine++;
    #    };
    #    $ThisLine=$lines[$FileLine]; 
    #    $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    #    @LineDat = split /[,\s]+/, $ThisLine;
    #    for(my $i=0;$i<($iGaps*2);$i++) {
    #        push(@GapsData,$LineDat[$i]);
    #    };
    #    
    # };
    
    # Load the conductivity and thickness of the layer
    $DataLine=0;
    until ($DataLine==$surfNum) {
        if($lines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {$DataLine++;}
        $FileLine++;
    };
    for(my $i=1;$i<=$iMatLayrs;$i++) {
        $ThisLine=$lines[$FileLine]; 
        $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        @LineDat = split /[,\s]+/, $ThisLine;
        push(@LayerCon,$LineDat[0]);
        push(@LayerThick,$LineDat[3]);
        $FileLine++;
    };
    
    # Calculate the RSI of construction
    for (my $i=0;$i<=$#LayerCon;$i++) {
        $OrigRSI+=$LayerThick[$i]/$LayerCon[$i];
    };
    # Store the original RSI value
    $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'original_RSI'} = $OrigRSI;
    
    # Upgrade the insulation if needed
    if($OrigRSI<$UpgradesSurf->{'max_RSI'}) {
        # Determine the amount of insulation to add
        my $AddedRSI = $UpgradesSurf->{'max_RSI'} - $OrigRSI;
        my $Thickness = $UpgradesSurf->{'ins_k'}*$AddedRSI; # Thickness of insulation needed [m]
        $strNewLayer = sprintf("%.3f %.1f %.1f %.3f 0 0 0 0 # Added blown in insulation (UPGRADE to RSI %.1f)\n",$UpgradesSurf->{'ins_k'},$UpgradesSurf->{'ins_rho'},$UpgradesSurf->{'ins_Cp'},$Thickness,$UpgradesSurf->{'max_RSI'} );
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'new_RSI'} = $UpgradesSurf->{'max_RSI'};
        
        # Add the new layer to the construction (inside face)
        @NewCons = @lines[0..($FileLine-1)];
        push(@NewCons,$strNewLayer);
        push(@NewCons,@lines[$FileLine..$#lines]);
        
        # Update number of layers
        $ThisLine=$lines[$IndexLayerGaps];
        $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        @LineDat = split /[,\s]+/, $ThisLine;
        $LineDat[0]++;
        my $NewLayers="";
        foreach my $ThatData (@LineDat) {
            $NewLayers = $NewLayers . "$ThatData ";
        };
        $NewLayers = $NewLayers."\n";
        $NewCons[$IndexLayerGaps] = $NewLayers;
        
        # Write the new construction file
        open my $out, '>', $conPath or die "Can't write $conPath: $!";
        foreach my $ThatData (@NewCons) {
            print $out $ThatData;
        };
        close $out;
        
        # If this surface has boundary condition "ANOTHER", update that con file as well
        if(defined($thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'boundary'})) {
            # Get other zone and surface names
            my $OtherZone = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'boundary'}->{'zone'};
            my $OtherSurf = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'boundary'}->{'surf'};
            
            # Construct path to other con file
            $conPath = $recPath . "$house_name" . ".$OtherZone" . ".con";
            
            # Load the other con file data
            open $ConFID, $conPath or die "Could not open $conPath\n";
            @lines = <$ConFID>; # Pull entire file into an array
            close $ConFID;
            
            # Get the surface number in this zone
            $surfNum = $thisHouse->{"$OtherZone"}->{'Surfaces'}->{"$OtherSurf"}->{'surf_num'};
            
            # Find the index to the layer info
            $DataLine=0;
            $FileLine=0;
            until (($lines[$FileLine] !~ m/^(#)/i) && ($DataLine==$surfNum)) {
                $FileLine++;
                if($lines[$FileLine] !~ m/^(#)/i){$DataLine++};
            };
            $IndexLayerGaps = $FileLine; # Store index to surface number of layers and gaps
            my $ThisLine=$lines[$FileLine]; 
            $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split /[,\s]+/, $ThisLine;
            $iMatLayrs = $LineDat[0];
            
            # Find the constructions data
            $DataLine=0;
            until ($DataLine==$surfNum) {
                if($lines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {$DataLine++;}
                $FileLine++;
            };
            
            # Reset the NewCon array
            @NewCons=@lines[0..($FileLine-1)];
            push(@NewCons,$strNewLayer);
            push(@NewCons,@lines[$FileLine..$#lines]);
            
            # Update the layer info
            $ThisLine=$lines[$IndexLayerGaps];
            $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split /[,\s]+/, $ThisLine;
            $LineDat[0]++;
            $NewLayers="";
            foreach my $ThatData (@LineDat) {
                $NewLayers = $NewLayers . "$ThatData ";
            };
            $NewLayers = $NewLayers."\n";
            $NewCons[$IndexLayerGaps] = $NewLayers;
            
            # Write the new construction file
            open my $out, '>', $conPath or die "Can't write $conPath: $!";
            foreach my $ThatData (@NewCons) {
                print $out $ThatData;
            };
            close $out;
        };
        
    } else { # Insulation is sufficient already
        $UPGrecords->{"$house_name"}->{"$zone"}->{"$surfname"}->{'new_RSI'}=$OrigRSI;
    };
    
    return $UPGrecords;

}; # END UpdateCONdata
# ====================================================================
# getZoneDataCFG
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
sub getZoneDataCFG {
    my ($rec,$path,$Surf) = @_;
    
    # Intermediates
    my $FileLine=0;
    my $ZoneCount=1;
    
    my $CFGpath = $path . "$rec/$rec.cfg";
    
    # Crack open the cfg file 
    my $cfgFID;
    open $cfgFID, $CFGpath or die "Could not open $CFGpath\n";
    my @lines = <$cfgFID>; # Pull entire file into an array
    close $cfgFID;
    
    ZONE_NUM: while($FileLine<=$#lines){
        until($lines[$FileLine] =~ m/^(\*zon\s)/) {
            $FileLine++;
            if ($FileLine>$#lines) {last ZONE_NUM;}
        };
        $FileLine++;
        my ($zone) = $lines[$FileLine] =~ /$rec\.([^.]+)/;
        $Surf->{"_$rec"}->{$zone}->{'zone_number'} = $ZoneCount;
        $ZoneCount++;
    }; # END ZONE_NUM

    return $Surf;

}; # END getZoneDataCFG
# ====================================================================
# getCNN
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
sub getCNN {
    my ($rec,$path,$SurfRec) = @_;
    
    # Intermediates
    my $FileLine=0;
    my $CurZone = 0;
    my $ThisZone = "";
    
    my $CFGpath = $path . "$rec/$rec.cnn";
    
    # Crack open the cfg file 
    my $cfgFID;
    open $cfgFID, $CFGpath or die "Could not open $CFGpath\n";
    my @lines = <$cfgFID>; # Pull entire file into an array
    close $cfgFID;
    
    SRT_CNN: until($lines[$FileLine] =~ m/^(#CONNECTIONS)/) {
        $FileLine++;
        if ($FileLine>$#lines) {last SRT_CNN;}
    };
    if ($FileLine>$#lines) {die "Could not file connections data in $CFGpath\n";}
    $FileLine++;
    EACH_CNN: until($lines[$FileLine] =~ m/^(#END_CONNECTIONS)/) {
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split /[,\s]+/, $lines[$FileLine];
        if($LineDat[0] > $CurZone) { # Connections for new zone
            $CurZone = $LineDat[0];
            foreach my $zonRec (keys (%{$SurfRec})) {
                if($SurfRec->{$zonRec}->{'zone_number'} == $LineDat[0]) {
                    $ThisZone = $zonRec;
                    last;
                };
            };
        };
        
        # Get the name of the current surface connection
        my $CurSurf; #  The name of the current surface
        foreach my $surfs (keys (%{$SurfRec->{"$ThisZone"}->{'Surfaces'}})) { # Find surface key
            if($SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$surfs"}->{'surf_num'} == $LineDat[1]) {
                $CurSurf = $surfs;
                last;
            };
        };
        if (not defined($CurSurf)) {die "Could not find surface name for current surface\n";}

        if($LineDat[2] == 3) { # This surface boundary condition is other
            foreach my $zonRec (keys (%{$SurfRec})) {
                if($SurfRec->{$zonRec}->{'zone_number'} == $LineDat[3]) {
                    foreach my $surfs (keys (%{$SurfRec->{"$zonRec"}->{'Surfaces'}})) {
                        if($SurfRec->{"$zonRec"}->{'Surfaces'}->{"$surfs"}->{'surf_num'} == $LineDat[4]) {
                            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'}->{'zone'} = $zonRec;
                            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'}->{'surf'} = $surfs;
                            last;
                        };
                    };
                    
                    last;
                };
            };
            
        } elsif($LineDat[2] == 0) { # Boundary is exterior
            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'} = 'exterior';
        } elsif($LineDat[2] == 6) { # Boundary is BASESIMP
            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'} = 'basesimp';
        };
        $FileLine++;
    };


    return $SurfRec;

}; # END getZoneDataCFG
# ====================================================================
# getBSMTType
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getBSMTType {
    
    my ($house_name,$recPath) = @_;
    
    # Intermediates
    my $FileLine=0;
    
    # Outputs
    my $BsmtIndex;
    
    # Load the cnn file
    my $cnnFile = $recPath . "$house_name.cnn";
    my $cnnfid;
    open $cnnfid, $cnnFile or die "Could not open $cnnFile\n";
    my @lines = <$cnnfid>; # Pull entire file into an array
    close $cnnfid;

    # Navigate to the connections
    SRT_CNN: until($lines[$FileLine] =~ m/^(#CONNECTIONS)/) {
        $FileLine++;
        if ($FileLine>$#lines) {last SRT_CNN;}
    };
    $FileLine++;
    while($FileLine<$#lines) {
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split /[,\s]+/, $lines[$FileLine];
        if(($LineDat[2]/1) == 6) { # BASESIMP connection, get the basesimp type
            $BsmtIndex = $LineDat[3];
            last;
        };
        $FileLine++;
    };

    return $BsmtIndex;
}; # END UpdateBSMfile
# ====================================================================
# setBSMfile
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setBSMfile {
    my ($house_name,$recPath,$BsmtIndex,$UpgradesBsmt,$UPGrecords) = @_;
    
    # Intermediates
    my @BSMdata=();
    my $FileLine=0;
    my $OldRSI;
    
    # Outputs
    my $newBSMtype;
    
    # Determine the ``new" foundation type
    $newBSMtype = getNewBsmType($BsmtIndex);
    
    # Load the bsm file
    my $cnnFile = $recPath . "$house_name.bsmt.bsm";
    my $cnnfid;
    open $cnnfid, $cnnFile or die "Could not open $cnnFile\n";
    my @lines = <$cnnfid>; # Pull entire file into an array
    close $cnnfid;
    
    # Scan the bsm file, pull the data
    while ($FileLine<=$#lines) { 
        if(($lines[$FileLine] !~ m/^(#)/) && ($lines[$FileLine] !~ m/^(\*)/)) {
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            push(@BSMdata,$lines[$FileLine]);
        };
        $FileLine++;
    };

    # Get the RSI value
    $OldRSI = $BSMdata[5];
    
    if ($OldRSI<$UpgradesBsmt->{'max_RSI'}) { # Increase the insulation
    
    } else {
    
    };
    
    print Dumper $UpgradesBsmt;
    sleep;
    
    
    
    return ($UPGrecords,$newBSMtype);
};
# ====================================================================
# getNewBsmType
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getNewBsmType {
    my $OldIndex = shift @_;
    
    # Outputs
    my $NewIndex;
    
    if(($OldIndex==1) || ($OldIndex==12) || ($OldIndex==14) || ($OldIndex==19) || ($OldIndex==20) || ($OldIndex==68) || ($OldIndex==69) || ($OldIndex==72) || ($OldIndex==92) || ($OldIndex==93) || ($OldIndex==94) || ($OldIndex==103) || ($OldIndex==108) || ($OldIndex==111) || ($OldIndex==112) || ($OldIndex==113) || ($OldIndex==114) || ($OldIndex==115) || ($OldIndex==121) || ($OldIndex==129) || ($OldIndex==133)) {
        $NewIndex = $OldIndex;
    } elsif($OldIndex==2) {
        $NewIndex = 1;
    } elsif($OldIndex==4) {
        $NewIndex = 1;
    } elsif($OldIndex==6) {
        $NewIndex = 96;
    } elsif($OldIndex==8) {
        $NewIndex = 12;
    } elsif($OldIndex==10) {
        $NewIndex = 1;
    } elsif($OldIndex==15) {
        $NewIndex = 14;
    } elsif($OldIndex==73) {
        $NewIndex = 72;
    } elsif($OldIndex==110) {
        $NewIndex = 69;
    } elsif($OldIndex==119) {
        $NewIndex = 96;
    } else {
        $NewIndex = -1;
    };
    
    return $NewIndex;
};

# Final return value of one to indicate that the perl module is successful
1;