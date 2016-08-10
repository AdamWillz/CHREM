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
use warnings;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Cwd;
use Data::Dumper;
use Switch;

use lib qw(./modules);
use PV;
use General qw(replace insert);

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(getGEOdata upgradeCeilIns setBCDpath upgradeBsmtIns upgradeAirtight upgradeDHsystem);
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
    my $newBSMtype;
    
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
    # Store the original BASESIMP type
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'orig_basesimp_code'} = $BsmtIndex;
        
    # Only apply insulation to foundation type `bsmt' and `crawl'
    if($strFdnType =~ m/bsmt/) {
        # Update the bsm file
        ($UPGrecords,$newBSMtype) = setBSMfile($house_name,$recPath,$BsmtIndex,$UpgradesBsmt,$UPGrecords);
        # Update the connections file if the foundation type has changed
        if($newBSMtype>0){setBsmCNN($house_name,$recPath,$newBSMtype);}
        # Store the foundation type
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'foundation_type'} = $strFdnType;
    } elsif($strFdnType =~ m/crawl/) { # Foundation crawlspace
        $UPGrecords = UpdateCONdataCRAWL($UpgradesBsmt,$house_name,$recPath,$thisHouse,$strFdnType,$UPGrecords);
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'foundation_type'} = $strFdnType;
    } else { # Foundation is slab
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'foundation_type'} = $strFdnType;
    };

    return $UPGrecords;

}; # END upgradeCeilIns
# ====================================================================
# upgradeAirtight
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeAirtight {
    # INPUTS
    my ($house_name,$UpgradesAIM2,$setPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $OldACH;
    my $NewACH; # The new ACH to achieve at 50 delta_P
    my $DataLines=0;
    my $FileLine=0;
    my $ThisLine;
    my $recPath = $setPath . "$house_name/";
    my $iVentType; # The ventilation system to be upgraded to
    my $sVentType; # The ventilation system to be upgraded to (string)
    my $iVentTypeORG; # The original dwelling ventilation system type
    my $fCurrentVent; # The original dwelling ventilation flow rate
    my $fVentFlowRequired; # The flow rate required based on ASHRAE Standard 62.2-2016
    
    # Determine the new ACH to achieve
    if($UpgradesAIM2->{'INFIL'}->{'type'} =~ m/default/) {
        $NewACH = getDefaultACH($UpgradesAIM2->{'INFIL'}->{'level'});
    } elsif($UpgradesAIM2->{'INFIL'}->{'type'} =~ m/custom/) {
        $NewACH = $UpgradesAIM2->{'INFIL'}->{'ACH_50'};
    } else {
        die "Invalid AIM-2 upgrade type $UpgradesAIM2->{'type'}. Options are default and custom\n";
    };

    # Load the aim2 file
    my $AimFile = $recPath . "$house_name.aim";
    my $fid;
    open $fid, $AimFile or die "Could not open $AimFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Determine the blower door data
    while($FileLine<=$#lines) {
        if($lines[$FileLine] !~ m/^(#)/) {$DataLines++;}
        if($DataLines==2) {last;}
        $FileLine++;
    };
    if($FileLine>=$#lines){die "Could not load AIM-2 data\n";}
    $ThisLine = $lines[$FileLine];
    $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split /[,\s]+/, $ThisLine;
    $OldACH = $LineDat[2];
    if((not defined($LineDat[2])) || $OldACH<=0) {die "There was an error reading the AIM-2 blower door data\n";}
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'orig_ACH50'} = $OldACH;
    
    # Determine if the airtightness needs to be increased
    if($OldACH<=$NewACH) { # Acceptable tightness level already
        $NewACH = $OldACH;
    } elsif($UpgradesAIM2->{'INFIL'}->{'type'} =~ m/default/) {
        $lines[$FileLine] = "$UpgradesAIM2->{'INFIL'}->{'level'}\n";
    } else {
        $lines[$FileLine] = "1 3 $UpgradesAIM2->{'INFIL'}->{'ACH_50'} $UpgradesAIM2->{'INFIL'}->{'ELA_Pa'} $UpgradesAIM2->{'INFIL'}->{'ELA'} $UpgradesAIM2->{'INFIL'}->{'Cd'}\n";
    };
    
    # Record the new ACH @ 50 delta_P
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'new_ACH50'} = $NewACH;
    
    # Print the updated AIM-2 file
    if($OldACH != $NewACH) { # There have been changes to the AIM-2 file
        open my $out, '>', $AimFile or die "Can't write $AimFile: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;
    };
    
    #================================================================
    # VENTILATION
    #================================================================
    # What is the required ventilation rate for the dwelling airtightness
    $fVentFlowRequired = getDwellingVentilationRate($house_name,$recPath);
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'Reqd_Vent_Ls'} = $fVentFlowRequired;
    
    # Determine if there is an existing ventilation system
    $iVentTypeORG = getVentType($house_name,$recPath);
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'orig_CVS'} = $iVentTypeORG;

    # If there is a ventilation system, retrieve the flow rate
    if($iVentTypeORG>1) {
        $fCurrentVent = getVentFlowRate($house_name,$recPath,$iVentTypeORG);
    } else {
        $fCurrentVent = 0.0;
    };
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'orig_Vent_Ls'} = $fCurrentVent;

    # Determine the user-prescribed ventilation system type to upgrade to
    if(defined($UpgradesAIM2->{'HRV'}) && defined($UpgradesAIM2->{'ERV'})) {die "Error: Both an ERV and HRV have been defined in the upgrade input file.\n";}
    if(defined($UpgradesAIM2->{'HRV'})) {
        $iVentType = 2;
        $sVentType = 'HRV';
    } elsif (defined($UpgradesAIM2->{'ERV'})) {
        $iVentType = 4;
        $sVentType = 'ERV';
        die "Currently ERV upgrades are unsupported. ESP-r's moisture balance subroutines are a horrible mess\nThis tool does have the structure in place to add ERVs to the model however\n";
    } else { # Fans with no heat recovery
        $iVentType = 3;
        $sVentType = 'FAN';
    };

    # Determine if an upgrade needs to occur
    if(($fCurrentVent<$fVentFlowRequired) || ($iVentTypeORG!=$iVentType)) {
        $UPGrecords = setVNTfile($house_name,$recPath,$iVentType,$sVentType,$fVentFlowRequired,$UpgradesAIM2,$UPGrecords);
    };

    return $UPGrecords;
};
# ====================================================================
# upgradeDHsystem
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeDHsystem {
    # INPUTS
    my ($house_name,$UpgradesDH,$ThisSurfaces,$setPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    
    # Interrogate this dwellings HVAC file
    $UPGrecords = getHVACdata($house_name,$setPath,$UPGrecords);
    
    # Interrogate this dwelling's DHW system
    $UPGrecords = getDHWdata($house_name,$setPath,$UPGrecords);
    
    # Remove the heating system from dwelling
    setHVACfileDH($house_name,$setPath,$UPGrecords);
    
    # Remove the DHW system from dwelling
    setDHWfileDH($house_name,$setPath,$UPGrecords);
    
    return $UPGrecords;
};
# ====================================================================
# *********** PRIVATE METHODS ***************
# ====================================================================

# ====================================================================
# *********** CEILING INSULATION SUBROUTINES ***************
# ====================================================================

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
        
        # Store the upgrade data for post-processing and record keeping
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'new_RSI'} = $UpgradesSurf->{'max_RSI'};
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'ins_thickness'} = $Thickness; # Thickness of insulation added
        
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
# *********** BASEMENT INSULATION SUBROUTINES ***************
# ====================================================================

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
    my $effRSI;
    my $newRSI;
    my $sInsFacing;

    # Outputs
    my $newBSMtype;
    
    # Determine the "new" foundation type
    $newBSMtype = getNewBsmType($BsmtIndex);
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'new_basesimp_code'} = $newBSMtype;
    
    # Load the bsm file
    my $cnnFile = $recPath . "$house_name.bsmt.bsm";
    my $cnnfid;
    open $cnnfid, $cnnFile or die "Could not open $cnnFile\n";
    my @lines = <$cnnfid>; # Pull entire file into an array
    close $cnnfid;
    
    # Scan the bsm file, pull the data
    while ($FileLine<=$#lines) { 
        if(($lines[$FileLine] !~ m/^(#)/) && ($lines[$FileLine] !~ m/^(\*)/)) {
            my $Retrieve = $lines[$FileLine];
            $Retrieve =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            push(@BSMdata,$Retrieve);
        };
        $FileLine++;
    };

    # Get the RSI value
    $OldRSI = $BSMdata[5];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'orig_RSI'} = $OldRSI;
    
    # Get effective wall RSI
    $sInsFacing = getBsmtWallInsLocation($BsmtIndex); # First, determine if the walls are insulated on the inside and outside
    if($sInsFacing =~ m/both/) {
        $effRSI = $OldRSI*2.0;
    } elsif ($sInsFacing =~ m/none/) {
        $effRSI = 0.0;
    } else {
        $effRSI = $OldRSI;
    };
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'orig_eff_RSI'} = $effRSI;
    
    # Store other relevant data for post-processing
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'height'} = $BSMdata[0];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'depth'} = $BSMdata[1];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'length'} = $BSMdata[2];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'width'} = $BSMdata[3];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'overlap'} = $BSMdata[4];
    
    # Initialize the area of insulation added to basement
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'area_ins_added'} = 0.0;
    
    if ($effRSI<$UpgradesBsmt->{'bsmt'}->{'max_RSI'}) { # Increase the insulation
        my $Overlap;
        my $Newdata;
        my $NewEffRSI;
        my $BsmtWallArea;
        $FileLine = 0;
        if(($BsmtIndex == 8) && ($newBSMtype == 12)) { # Need to specify an overlap
            # Assume 0.2 m gap on inside insulation
            $Overlap = $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'depth'} - 0.2;
            until($lines[$FileLine] =~ m/(OVERLAP)/) {$FileLine++;}
            $FileLine++;
            $Newdata = sprintf("%.2f\n",$Overlap);
            $lines[$FileLine] = $Newdata;
        };
        
        # Determine the new RSI input to BASESIMP
        $newRSI = getNewRSIBsmt($BsmtIndex,$newBSMtype,$OldRSI,$UpgradesBsmt->{'bsmt'}->{'max_RSI'});
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'new_RSI'} = $newRSI;
        $sInsFacing = getBsmtWallInsLocation($newBSMtype);
        if($sInsFacing =~ m/both/) {
            $NewEffRSI = $newRSI*2.0;
        } elsif ($sInsFacing =~ m/none/) {
            $NewEffRSI = 0.0;
        } else {
            $NewEffRSI = $newRSI;
        };
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'new_eff_RSI'} = $NewEffRSI;
        
        # Record the area of insulation added
        $BsmtWallArea = (2*($UPGrecords->{'BASE_INS'}->{"$house_name"}->{'width'}+$UPGrecords->{'BASE_INS'}->{"$house_name"}->{'length'}))*$UPGrecords->{'BASE_INS'}->{"$house_name"}->{'height'};
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'area_ins_added'} = $BsmtWallArea;
        
        until($lines[$FileLine] =~ m/(#RSI)/) {$FileLine++;}
        $FileLine++;
        
        $Newdata = sprintf("%.2f\n",$newRSI);
        $lines[$FileLine] = $Newdata;

        # Print the new basesimp file
        open my $out, '>', $cnnFile or die "Can't write $cnnFile: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;

    };
    
    if ($BsmtIndex == $newBSMtype) {$newBSMtype=-1;}
    return ($UPGrecords,$newBSMtype);
};
# ====================================================================
# getNewBsmType
#       This subroutine assigns a new BASESIMP foundation type for insulation 
#       retrofits. It is assumed that any new insulation will be applied to
#       interior foundation walls, and be the full length.
#
# INPUT     The original BASESIMP foundation code (integer)
# OUTPUT    The new BASESIMP foundation code (integer)
# ====================================================================
sub getNewBsmType {
    my $OldIndex = shift @_;
    
    # Outputs
    my $NewIndex;
    
    switch ($OldIndex) {
		case 2		{$NewIndex = 1;}
		case 4	    {$NewIndex = 1;}
		case 6	    {$NewIndex = 96;}
		case 8	    {$NewIndex = 12;}
		case 10	    {$NewIndex = 1;}
		case 15	    {$NewIndex = 14;}
		#case 18	 {$NewIndex = 14;}
        case 71     {$NewIndex = 94;}
        #case 89     {$NewIndex = 111;}
        case 98     {$NewIndex = 93;}
        #case 99     {$NewIndex = ???}
		case 110	{$NewIndex = 69;}
        case 119    {$NewIndex = 22;}
		else		{$NewIndex=$OldIndex;}
	}
    
    return $NewIndex;
};
# ====================================================================
# UpdateCONdataCRAWL
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub UpdateCONdataCRAWL{
    my ($UpgradesSurf,$house_name,$recPath,$thisHouse,$zone,$UPGrecords) = @_;
    
    # Intermediates
    my $IndexLayerGaps; # Holds the line index in con file for number of layers and gaps
    my $iMatLayrs;
    
    my $conPath = $recPath . "$house_name" . ".$zone" . ".con";
    my $strNewLayer; # String to hold the new layer data
    my $bIsConModified = 0;
    my $Thickness = $UpgradesSurf->{'crawl'}->{'max_RSI'}*$UpgradesSurf->{'crawl'}->{'ins_k'}; # Thickness of insulation needed [m]
    
    # Outputs
    my $OrigRSI=0;
    my $NewRSI;
    
    # Load this zone's construction file
    my $ConFID;
    open $ConFID, $conPath or die "Could not open $conPath\n";
    my @lines = <$ConFID>; # Pull entire file into an array
    close $ConFID;
    
    CRAWL_WALL: foreach my $surfs (keys (%{$thisHouse->{"$zone"}->{'Surfaces'}})){
        if(($surfs =~ m/floor/) || ($surfs =~ m/ceiling/)) {next;} # Only upgrade the walls of the crawlspace
        my @LayerCon=();
        my @LayerThick=();
        my @NewCons=();
        my $iInsLayer=0;
        
        # Get the surface number
        my $surfNum = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfs"}->{'surf_num'};
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
        
        # Load the conductivity and thickness of the layer
        $DataLine=0;
        until ($DataLine==$surfNum) {
            if($lines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {$DataLine++;}
            $FileLine++;
        };
        for(my $i=1;$i<=$iMatLayrs;$i++) {
            $ThisLine=$lines[$FileLine]; 
            $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            if($ThisLine =~ m/(insulation)/) {$iInsLayer=$FileLine}; # Locate the layer with insulation, store the line number
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
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{"$zone"}->{"$surfs"}->{'original_RSI'} = $OrigRSI;
        
        # Upgrade the insulation if needed
        if($OrigRSI<$UpgradesSurf->{'crawl'}->{'max_RSI'}) {
            $bIsConModified = 1; # Record that a change to the construction is being made
           
            # Format the new insulation layer
            $strNewLayer = sprintf("%.3f %.1f %.1f %.3f 0 0 0 0 # New crawlspace insulation (UPGRADE to RSI %.1f)\n",$UpgradesSurf->{'crawl'}->{'ins_k'},$UpgradesSurf->{'crawl'}->{'ins_rho'},$UpgradesSurf->{'crawl'}->{'ins_Cp'},$Thickness,$UpgradesSurf->{'crawl'}->{'max_RSI'} );
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{"$zone"}->{"$surfs"}->{'new_RSI'} = $UpgradesSurf->{'crawl'}->{'max_RSI'};
            
            # Add the new layer to the construction (inside face)
            if($iInsLayer==0) { # An additional layer must be added (inside face)
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
            } else { # Replace the insulation layer
                @NewCons = @lines;
                $NewCons[$iInsLayer] = $strNewLayer;
            };
            
            # Save changes to the con file
            @lines = @NewCons;

        } else { # Insulation is sufficient already
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'left'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'right'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'front'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'back'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            last CRAWL_WALL;
        };
    }; # END CRAWL_WALL

    # Write the new construction file
    if($bIsConModified){
        open my $out, '>', $conPath or die "Can't write $conPath: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;
    };

    return $UPGrecords;

}; # END UpdateCONdataCRAWL
# ====================================================================
# getBsmtWallInsLocation
#       Determines if the foundation walls are insulated on both-sides 
#       (1) or only on the interior/exterior (0)
#
# INPUT     BsmtIndex: BASESIMP foundation code
# OUTPUT    bInsBothSides: Boolean to indicate if both sides of the 
#                          foundation wall are insulated
# ====================================================================
sub getBsmtWallInsLocation {
    # INPUTS
    my $BsmtIndex = @_;
    
    # OUTPUTS
    my $sWallIns;
    
    switch ($BsmtIndex) {
		case [1,2,4,14,15,19,20,72,73,103,108,111,112,113,119,121,133]	{ $sWallIns = 'inside'; }
		case [6,8,18,71,89,98,99,110,129]	{ $sWallIns = 'outside'; }
        case 10	{ $sWallIns = 'none'; }
		else    { $sWallIns = 'both'; }
	}
    
    return $sWallIns;
};
# ====================================================================
# getEffectiveBsmtRSI
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setBsmCNN {
    my ($house_name,$recPath,$NewBSM) = @_;
    # TODO: TEST SUBROUTINE
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
        my $Retrieve = $lines[$FileLine];
        $Retrieve =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split /[,\s]+/, $Retrieve;
        if(($LineDat[2]/1) == 6) { # BASESIMP connection, get the basesimp type
            my $NewData="";
            for (my $i=0;$i<=$#LineDat;$i++) {
                if($i != 3) {
                    $NewData = $NewData . "$LineDat[$i] ";
                } else {
                    $NewData = $NewData . "$NewBSM ";
                };
            };
            $NewData = $NewData . "\n";
            $lines[$FileLine] = $NewData;
        };
        $FileLine++;
    };
    
    # Print the new basesimp file
    open my $out, '>', $cnnFile or die "Can't write $cnnFile: $!";
    foreach my $ThatData (@lines) {
        print $out $ThatData;
    };
    close $out;
    
    return;
};
# ====================================================================
# getNewRSIBsmt
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getNewRSIBsmt {
    # INPUTS
    my ($BsmtIndex,$newBSMtype,$OldRSI,$NewRSI) = @_;
    
    # OUTPUTS
    my $EquivRSI = $NewRSI;
    
    # INTERMEDIATES
    my $sOldFacing;
    my $sNewFacing;
    
    $sOldFacing = getBsmtWallInsLocation($BsmtIndex);
    $sNewFacing = getBsmtWallInsLocation($newBSMtype);
    
    if (($sNewFacing =~ m/both/) && (($sOldFacing =~ m/outside/) || ($sOldFacing =~ m/both/))) {
        $EquivRSI = ($OldRSI+$NewRSI)/2.0;
    };

    return $EquivRSI;
};
# ====================================================================
# *********** AIRTIGHTNESS SUBROUTINES ***************
# ====================================================================

# ====================================================================
# getDefaultACH
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getDefaultACH {
    # INPUT
    my $Aim2Type = shift @_;

    # OUTPUT
    my $DefaultACH;
    
    switch ($Aim2Type) {
		case 3		{ $DefaultACH = 10.35; }
        case 4		{ $DefaultACH = 4.55; }
        case 5		{ $DefaultACH = 3.57; }
        case 6		{ $DefaultACH = 1.50; }
		else		{ die "Invalid default AIM-2 type $Aim2Type\n"; }
	}
    
    return $DefaultACH;
};
# ====================================================================
# setVNTfile
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setVNTfile {
    # INPUTS
    my ($house_name,$recPath,$iVentTypeUPG,$sVentType,$fVentFlowRequired,$UpgradesAIM2,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0;
    my $RVData; # HASH hold the HRV or ERV data

    # Load the mvnt template file
    my $TmpFile = "../templates/template.mvnt";
    my $fid;
    open $fid, $TmpFile or die "Could not open $TmpFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;

    if ($iVentTypeUPG == 2 || $iVentTypeUPG == 4) {	# Upgrade to HRV or ERV
        # Determine which device to use for this house
        my $sDeviceIndex;
        # Load the device data
        $RVData = $UpgradesAIM2->{"$sVentType"};
        # Load the available supply flow rates
        my @FlowRates = @{$UpgradesAIM2->{"$sVentType"}->{'flowrate'}};
        @FlowRates = sort { $a <=> $b } @FlowRates; # Sort the flowrates from high to low
        # Find a device that meets the ventilation requirements
        my $i=0;
        until(($FlowRates[$i]>=$fVentFlowRequired) || ($i==$#FlowRates)){$i++;}
        $sDeviceIndex = 'Supply_' . "$FlowRates[$i]";
        $fVentFlowRequired = $FlowRates[$i];

        # Set the CVS system type 
        &replace (\@lines, "#CVS_SYSTEM", 1, 1, "%s\n", "$iVentTypeUPG");	# list CSV as HRV
        
        # Load the device data
        my $hsp_T = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'hsp_T'};
        my $hsp_SRE = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'hsp_SRE'};
        my $hsp_P = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'hsp_P'};
        my $vltt_T = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'vltt_T'};
        my $vltt_SRE = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'vltt_SRE'};
        my $vltt_P = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'vltt_P'};
        my $tre = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'tre'};
        my $Preheat_P = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'Preheat_P'};
        my $hsp_LRMT;
        my $vltt_LRMT;
        if($iVentTypeUPG == 4){ # additional ERV data
            $hsp_LRMT = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'hsp_LRMT'};
            $vltt_LRMT = $UpgradesAIM2->{"$sVentType"}->{"$sDeviceIndex"}->{'vltt_LRMT'};
            &insert (\@lines, "#HRV_DATA", 1, 1, 0, "%s\n%s\n", "$hsp_T $hsp_SRE $hsp_LRMT $hsp_P", "$vltt_T $vltt_SRE $vltt_LRMT $vltt_P");	# list efficiency and fan power (W) at cool (0C) and cold (-25C) temperatures. NOTE: Fan power is set to zero as electrical casual gains are accounted for in the elec and opr files. If this was set to a value then it would add it to the incoming air stream and report it to SiteUtilities
        } else {
            &insert (\@lines, "#HRV_DATA", 1, 1, 0, "%s\n%s\n", "$hsp_T $hsp_SRE $hsp_P", "$vltt_T $vltt_SRE $vltt_P");	# list efficiency and fan power (W) at cool (0C) and cold (-25C) temperatures. NOTE: Fan power is set to zero as electrical casual gains are accounted for in the elec and opr files. If this was set to a value then it would add it to the incoming air stream and report it to SiteUtilities
        };
        &insert (\@lines, "#HRV_FLOW_RATE", 1, 1, 0, "%s\n", $fVentFlowRequired);	# supply flow rate
        &insert (\@lines, "#HRV_COOL_DATA", 1, 1, 0, "%s\n", "$tre");	# cool efficiency
        &insert (\@lines, "#HRV_PRE_HEAT", 1, 1, 0, "%s\n", "$Preheat_P");	# preheat watts
        &insert (\@lines, "#HRV_TEMP_CTL", 1, 1, 0, "%s\n", "7 0 0");	# this is presently not used (7) but can make for controlled HRV by temp
        &insert (\@lines, "#HRV_DUCT", 1, 1, 0, "%s\n%s\n", "1 1 2 2 152 0.1", "1 1 2 2 152 0.1");	# use the typical duct values
    }
    elsif ($iVentTypeUPG == 3) {	# fan only ventilation
        &replace (\@lines, "#CVS_SYSTEM", 1, 1, "%s\n", "$iVentTypeUPG");	# list CSV as fan ventilation
        &insert (\@lines, "#VENT_FLOW_RATE", 1, 1, 0, "%s\n", "$fVentFlowRequired $fVentFlowRequired 0");	# supply and exhaust flow rate (L/s) and fan power (W) NOTE: Fan power is set to zero as electrical casual gains are accounted for in the elec and opr files. If this was set to a value then it would add it to the incoming air stream and report it to SiteUtilities
        &insert (\@lines, "#VENT_TEMP_CTL", 1, 1, 0, "%s\n", "7 0 0");	# no temp control
    };	# no need for an else
    
    # Print the new mvnt file
    my $MvntFile = $recPath . "$house_name.mvnt";
    unlink $MvntFile; # Clear the old file
    open my $out, '>', $MvntFile or die "Can't write $MvntFile: $!";
    foreach my $ThatData (@lines) {
        print $out $ThatData;
    };
    close $out;
    
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'new_CVS'} = $iVentTypeUPG;
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'new_Vent_Ls'} = $fVentFlowRequired;

    return $UPGrecords;
};
# ====================================================================
# getVentType
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getVentType {
    # INPUTS
    my ($house_name,$recPath) = @_;
    
    # OUTPUT
    my $iVentType;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    
    # Load the mvnt file
    my $MvntFile = $recPath . "$house_name.mvnt";
    my $fid;
    open $fid, $MvntFile or die "Could not open $MvntFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Load the ventilation data from the file (first item)
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $iVentType = $lines[$FileLine];
    $iVentType =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace

    return $iVentType;
};
# ====================================================================
# getDwellingVentilationRate
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getDwellingVentilationRate {
    # INPUT
    my ($house_name,$recPath) = @_;
    
    # OUTPUT
    my $fVentFlow;
    
    # INTERMEDIATES
    my $climate;
    my $swf;
    my $iAdults;
    my $iKids;
    my $fFloor;
    my $ELA;
    my $Height;
    my $fAnnInfil;
    my $fNominalVent;
    
    # Determine the weather and shielding factor
    $climate = getDwellingClimate($house_name,$recPath);
    $swf = getWeatherShieldingFactor($climate);
    
    # Determine the conditioned floor area and occupancy
    ($iAdults,$iKids,$fFloor) = getOccupantsFloorArea($house_name);
    
    # Determine the height and ELA of the dwelling
    ($Height,$ELA) = getDwellingHeightELA($house_name,$recPath);
    
    # Estimate the nominal ventilation rate required
    $fNominalVent = getNominalVentilation($iAdults,$iKids,$fFloor);
    
    # Determine the annual average infiltration
    $fAnnInfil = getAnnualAverageInfil($Height,$ELA,$swf,$fFloor);
    if($fAnnInfil>(($fNominalVent*2.0)/3.0)){$fAnnInfil=(($fNominalVent*2.0)/3.0);} # According to the standard
    
    # The total mechanical ventilation required
    $fVentFlow = $fNominalVent - $fAnnInfil; # Assume Aext = 1 (single-family detached home)
    $fVentFlow = sprintf("%.2f",$fVentFlow);
    
    return $fVentFlow;
};
# ====================================================================
# getDwellingClimate
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getDwellingClimate {
    # INPUT
    my ($house_name,$recPath) = @_;
    
    # OUTPUT
    my $climate;
    
    # INTERMEDIATES
    my $FileLine=0;
    
    # Load the cfg file
    my $CFGFile = $recPath . "$house_name.cfg";
    my $fid;
    open $fid, $CFGFile or die "Could not open $CFGFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Find the climate data
    until($lines[$FileLine] =~ m/^(\*clm)/) {$FileLine++;}
    
    # Parse out the climate zone
    $climate  = $lines[$FileLine];
    $climate =~ s/^\s+|\s+$//g;
    $climate =~ s/^.*[\/\\]//;
    $climate =~ s/\.[^.]+$//;

    return $climate;
};
# ====================================================================
# getWeatherShieldingFactor
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getWeatherShieldingFactor {
    # INPUT
    my ($climate) = @_;
    
    # OUTPUT
    my $swf;
    
    switch ($climate) {
		case "can_calgary"	    { $swf = 0.73; }
		case "can_montreal"	    { $swf = 0.60; }
        case "can_vancouver"	{ $swf = 0.57; }
        case "can_halifax"	    { $swf = 0.63; }
        case "can_toronto"	    { $swf = 0.58; }
		else		{ die "Sorry. Shielding and weather factor could not be found for $climate\nConsider adding value to subroutine getWeatherShieldingFactor in the UpgradeCity module.\n"; }
	}

    return $swf;
};
# ====================================================================
# getOccupantsFloorArea
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getOccupantsFloorArea {
    # INPUTS
    my ($house_name) = @_;
    
    # OUTPUTS
    my $iAdults;
    my $iKids;
    my $fFloor;
    
    # INTERMEDIATES
    my $FileLine=0;
    
    # Load in CHREM NN data
    my $NNinPath = '../NN/NN_model/ALC-Inputs-V2.csv';
    my $fid;
    open $fid, $NNinPath or die "Could not open $NNinPath\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    until($lines[$FileLine] =~ m/($house_name)/) {
        $FileLine++;
        if($FileLine>$#lines){die "Could not load the NN data for $house_name\n";}
    };
    
    # Parse the data
    $lines[$FileLine] =~ s/^\s+|\s+$//g;
    my @Parsed = split /[,]+/, $lines[$FileLine];
    
    # Get the data of interest
    $iAdults = $Parsed[55];
    $iKids   = $Parsed[54];
    $fFloor  = $Parsed[49];

    return($iAdults,$iKids,$fFloor);
};
# ====================================================================
# getDwellingHeightELA
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getDwellingHeightELA {
    # INPUTS
    my ($house_name,$recPath) = @_;
    
    # OUTPUTS
    my $Height;
    my $ELA;
    
    # INTERMEDIATES
    my $DataLine=0;
    my $FileLine=0;
    my $iAirType;
    
    # Load the AIM-2 file
    my $Aim2File = $recPath . "$house_name.aim";
    my $fid;
    open $fid, $Aim2File or die "Could not open $Aim2File\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Determine the airtightness type
    until($DataLine == 2){
        if($lines[$FileLine] !~ m/^(#)/){$DataLine++;}
        $FileLine++;
    }
    $FileLine--;
    $iAirType = $lines[$FileLine];
    $FileLine++;
    $iAirType =~ s/^\s+|\s+$//g;
    
    # Determine the ELA
    if($iAirType>2){ # Default leakage. Get the default ELA
        $ELA = getDefaultELA($iAirType);
    } else { # Read the ELA from the input file
        my @LineDat = split /[,\s]+/, $iAirType;
        $ELA = $LineDat[4]/1000.0;
    };
    
    # Get the height of the eaves
    until($DataLine == 5){
        if($lines[$FileLine] !~ m/^(#)/){$DataLine++;}
        $FileLine++;
    }
    $FileLine--;
    $Height = $lines[$FileLine];
    $Height =~ s/^\s+|\s+$//g;
    
    return($Height,$ELA);
};
# ====================================================================
# getDefaultELA
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getDefaultELA {
    # INPUT
    my $Aim2Type = shift @_;

    # OUTPUT
    my $DefaultELA;
    
    switch ($Aim2Type) {
		case 3		{ $DefaultELA = 0.11086; }
        case 4		{ $DefaultELA = 0.07292; }
        case 5		{ $DefaultELA = 0.06310; }
        case 6		{ $DefaultELA = 0.03423; }
		else		{ die "Invalid default AIM-2 type $Aim2Type\n"; }
	}
    
    return $DefaultELA;
};
# ====================================================================
# getNominalVentilation
#       This subroutine estimates the nominal ventilation requirement
#       of the dwelling based on number of adults and children. 
#       The required ventilation rate is calculated using ASHRAE 
#       Standard 62.2-2016.
#
# INPUT     iAdults: number of adults in the house
#           iKids: number of children in the house
#           fFloor: Heated floor area [m2]
# OUTPUT    fNominalVent: Total ventilation required for dwelling [L/s]
# ====================================================================
sub getNominalVentilation {
    # INPUTS
    my ($iAdults,$iKids,$fFloor) = @_;
    
    # OUTPUT
    my $fNominalVent;
    
    # INTERMEDIATES
    my $iBedrooms;
    
    # Estimate the number of bedrooms in the dwelling based on occupancy
    # First, assume one bedroom per occupants
    $iBedrooms = $iAdults+$iKids;
    # If there are at least 2 adults, assume one couple shares a room
    if($iAdults>1){$iBedrooms--};
    
    # Calculate the required nominal ventilation
    $fNominalVent = (0.15*$fFloor) +(3.5*($iBedrooms+1));
    
    return $fNominalVent;
}
# ====================================================================
# getAnnualAverageInfil
#       This subroutine estimates the average annual infiltration rate
#       This rate is calculated using ASHRAE Standard 62.2-2016.
#
# INPUT     Height: Vertical distance between the lowest and highest
#                   point in the pressure boundary above grade [m]
#           ELA: Effective leakage area [m2]
#           swf: weather and sheilding factor
#           fFloor: Heated floor area [m2]
# OUTPUT    fAnnInfil: Annual average infiltration rate [L/s]
# ====================================================================
sub getAnnualAverageInfil {
    # INPUTS
    my ($Height,$ELA,$swf,$fFloor) = @_;
    
    # OUTPUT
    my $fAnnInfil;
    
    # INTERMEDIATES
    my $NL;
    
    # Calculate the normalized leakage
    $NL = (1000.0*($ELA/$fFloor))*(($Height/2.5)**0.4);
    
    # Calculate the average annual infiltration rate
    $fAnnInfil = ($NL*$swf*$fFloor)/1.44;
    
    return $fAnnInfil;
};
# ====================================================================
# getVentFlowRate
#       This subroutine estimates the average annual infiltration rate
#       This rate is calculated using ASHRAE Standard 62.2-2016.
#
# INPUT     Height: Vertical distance between the lowest and highest
#                   point in the pressure boundary above grade [m]
#           ELA: Effective leakage area [m2]
#           swf: weather and sheilding factor
#           fFloor: Heated floor area [m2]
# OUTPUT    fAnnInfil: Annual average infiltration rate [L/s]
# ====================================================================
sub getVentFlowRate {
    # INPUTS
    my ($house_name,$recPath,$iVentTypeORG) = @_;
    
    # OUT
    my $fVentFlow;
    
    # INTERMEDIATES
    my $FileLine=0;
    my $DataLine=0;
    my $StopLine;
    
    # Open the mvnt file (again likely...)
    my $MvntFile = $recPath . "$house_name.mvnt";
    my $fid;
    open $fid, $MvntFile or die "Could not open $MvntFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Index the location of the ventilation flowrate
    if(($iVentTypeORG == 2) || ($iVentTypeORG == 4)) {
        $StopLine = 4;
    } elsif($iVentTypeORG == 3) {
        $StopLine = 2;
    } else {die"getVentFlowRate: Invalid ventilation system type $iVentTypeORG\n";}
    until($DataLine == $StopLine) {
        if($lines[$FileLine] !~ m/^(#)/) {$DataLine++;}
        $FileLine++;
    };
    $FileLine--;
    
    # Read the ventilation rate (L/s)
    $lines[$FileLine] =~ s/^\s+|\s+$//g;
    my @LineDat = split /[,\s]+/, $lines[$FileLine];
    $fVentFlow = $LineDat[0];
    
    return $fVentFlow;
};

# ====================================================================
# *********** DH SYSTEM SUBROUTINES ***************
# ====================================================================

# ====================================================================
# getHVACdata
#       This subroutine opens the dwelling HVAC file, determines the
#       current system type, and store the data in the upgrade HASH
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub getHVACdata {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $iSystems; # Integer holding number of HVAC systems
    my $fAltitude; # Altitude of system [m]

    # Load the mvnt file
    my $HVACFile = $recPath . "$house_name/$house_name.hvac";
    my $fid;
    open $fid, $HVACFile or die "getHVACdata: Could not open $HVACFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Get the number of HVAC systems present
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split ' ', $lines[$FileLine];
    $iSystems = $LineDat[0];
    $fAltitude = $LineDat[1];
    $FileLine++;
    # Store number of HVAC systems
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'Num_HVAC_Sys'} = $iSystems;
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'altitude'} = $fAltitude;
    
    # Get the HVAC system data
    for(my $i=1;$i<=$iSystems;$i++) {
        my $sSysType; # HVAC system type
        my $iNumZones;   # Number of zones serviced
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split ' ', $lines[$FileLine];
        $FileLine++;
        
        # What type of system this is
        if($LineDat[0] == 1) {
            $sSysType = 'furnace';
        } elsif($LineDat[0] == 7) {
            $sSysType = 'AC_HP';
        } elsif($LineDat[0] == 3) {
            $sSysType = 'baseboards';
        } elsif($LineDat[0] == 8) {
            $sSysType = 'GSHP';
            print "getHVACdata: Record $house_name, warning record has GSHP system. This type is not handled by Upgrade script\n";
        } elsif($LineDat[0] == 9) {
            $sSysType = 'GCEP';
             print "getHVACdata: Record $house_name, warning record has GCEP system. This type is not handled by Upgrade script\n";
        } else {
            die "getHVACdata: Unrecognized HVAC system $LineDat[0]. Should be 1,3 or 7,8,9\n";
        };
        #if($LineDat[1] != 1) {die "Record $house_name: HVAC has secondary system $LineDat[1]\n";}
        if($LineDat[1] == 1) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'priority'} = 'primary';
        } elsif ($LineDat[1] == 2) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'priority'} = 'secondary';
        } else {
            die "getHVACdata: Record $house_name, unrecognized system priority $LineDat[1]\n";
        };
        
        # How many zones are serviced
        $iNumZones = $LineDat[2];
        $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'Num_Zones_Served'} = $iNumZones;
        
        # Get the system data
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        @LineDat = split ' ', $lines[$FileLine];
        $FileLine++;
        
        if($sSysType =~ m/furnace/) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'Type'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'energy_src'} = $LineDat[1];
            my $iData = 2;
            for(my $j=1;$j<=$iNumZones;$j++){
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'Zone_num'} = $LineDat[$iData];
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'distribution'} = $LineDat[$iData+1];
                $iData = $iData+2;
            };
            $iData--;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'heating_capacity_W'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'efficiency'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'auto_circulation_fan'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'estimate_fan_power'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'draft_fan_power'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'pilot_power'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'duct_system_flag'} = $LineDat[$iData];

        } elsif(($sSysType =~ m/AC_HP/) || ($sSysType =~ m/GSHP/) || ($sSysType =~ m/GCEP/)) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'heating_or_cooling'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'Type'} = $LineDat[1];
            my $iData = 2;
            for(my $j=1;$j<=$iNumZones;$j++){
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'Zone_num'} = $LineDat[$iData];
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'distribution'} = $LineDat[$iData+1];
                $iData = $iData+2;
            };
            
            # Get the capacity and COP
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            my @LineDat = split ' ', $lines[$FileLine];
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'capacity_W'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'COP'} = $LineDat[1];
            
            # Get fan info
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $lines[$FileLine];
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'flow_rate'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'flow_at_rated'} = $LineDat[1];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_mode'} = $LineDat[2];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_position'} = $LineDat[3];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_power'} = $LineDat[4];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'outdoor_fan_power'} = $LineDat[5];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_power_auto_mode'} = $LineDat[6];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_pos_at_rated'} = $LineDat[7];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_power_at_rated'} = $LineDat[8];
            
            # Get sensible heat ratio and economizer type
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $lines[$FileLine];
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'sensible_heat_ratio'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'economizer_type'} = $LineDat[1];

        } elsif($sSysType =~ m/baseboards/) {
            my $iData = 0;
            for(my $j=1;$j<=$iNumZones;$j++){
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'Zone_num'} = $LineDat[$iData];
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'distribution'} = $LineDat[$iData+1];
                $iData = $iData+2;
            };
            $iData--;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'heating_capacity_W'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'efficiency'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'auto_circulation_fan'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'estimate_fan_power'} = $LineDat[$iData];
        };

    };

    return $UPGrecords;
};
# ====================================================================
# getDHWdata
#       This subroutine opens the dwelling DHW file, determines the
#       current system type, and store the data in the upgrade HASH
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub getDHWdata {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $DataLine = 0; # Number of lines with data read
    my $iTanks; # Integer holding number of tanks
    my $BDCmult; # BCD multiplier

    # Load the dhw file
    my $DHWFile = $recPath . "$house_name/$house_name.dhw";
    my $fid;
    open $fid, $DHWFile or die "Could not open $DHWFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Get the number of tanks present
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $FileLine++;
    $DataLine++; # Skip file version
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split ' ', $lines[$FileLine];
    $iTanks = $LineDat[0];
    $FileLine++;
    $DataLine++;
    # Store number of tanks
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'Num_Tanks'} = $iTanks;
    
    # Get the BCD multiplier
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $FileLine++;
    $DataLine++; # Skip the number of occupants
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    @LineDat = split ' ', $lines[$FileLine];
    $BDCmult = $LineDat[0];
    $FileLine++;
    $DataLine++;
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'BCD_Mult'} = $BDCmult;
    
    # Supply temperature (The supply temperature is hard coded to 60oC in ESP-r)
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $FileLine++;
    $DataLine++;
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'T_supply'} = 60.0;

    
    # Get the tank data
    my @sDHWKeys = qw(DHW_zone energy_src tank_type fDOEEF fHeatInjectorPower fPilotEnergyRate fTankSize fTemperatureBand fBlanketRSI);
    for(my $i=1;$i<=$iTanks;$i++) { # For each tank
        foreach my $dataa (@sDHWKeys) {
            my $ThisDHWdata;
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $lines[$FileLine];
            $ThisDHWdata = $LineDat[0];
            $DataLine++;
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{"$dataa"}->{'DHW_zone'} = $ThisDHWdata;
        };
    };

    return $UPGrecords;
};
# ====================================================================
# setHVACfileDH
#       This subroutine removes the heating system from the .hvac
#       file
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub setHVACfileDH {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $iSystems; # Integer holding number of HVAC systems
    my $fAltitude; # Altitude of system [m]
    my $iLineTop; # Marks the upper boundary of data to be retained
    my $iNewSystems;
    my @sNewHVAC;

    # Load the hvac file
    my $HVACFile = $recPath . "$house_name/$house_name.hvac";
    my $fid;
    open $fid, $HVACFile or die "Could not open $HVACFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Load number of HVAC systems
    $iSystems = $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'Num_HVAC_Sys'};
    $fAltitude = $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'altitude'};
    $iNewSystems = $iSystems;
    
    # Get the top of the hvac file
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $iLineTop = $FileLine;
    $FileLine++;
    @sNewHVAC = @lines[0..$iLineTop]; # Store the top of the hvac file
    
    # Begin cycling through the hvac systems, removing heating
    for(my $i=1;$i<=$iSystems;$i++) {
        my $iSysType;
        my $ThisHVACstart = $FileLine; # marks the start of this HVAC system data
        my $iTHisData = 0; # Data lines read in for this HVAC system
        my $iThisNumData = 0; # Number of data lines for this hvac type
        # Get the info for this system
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split ' ', $lines[$FileLine];
        $FileLine++;
        $iTHisData++;
        $iSysType = $LineDat[0];

        if (($iSysType == 1) || ($iSysType == 3)) { # Furnace or baseboard. Remove
            $iThisNumData = 2; # Both furnaces and baseboards have only 2 data lines
            until($iTHisData == $iThisNumData) {
                if ($lines[$FileLine] !~ m/^(#)/) {$iTHisData++;}
                $FileLine++;
            };

            # Decrement the number of HVAC systems
            $iNewSystems--;
            
        } elsif ($iSysType == 7) { # air-source heat pump
            my $iUnitFunction;
        
            # Determine if this heating or cooling
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            my $DummyLine = $lines[$FileLine];
            $DummyLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $DummyLine;
            $iUnitFunction = $LineDat[0];
            
            if($iUnitFunction == 2) { # Cooling
                $iThisNumData = 9;
                my $ThisHVACstop;
                until($iTHisData == $iThisNumData) {
                    if ($lines[$FileLine] !~ m/^(#)/) {$iTHisData++;}
                    $FileLine++;
                };
                
                # Grab the control data
                $DummyLine = $lines[$FileLine-1];
                $DummyLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                @LineDat = split ' ', $DummyLine;
                my $iCoolCtrl = $LineDat[1];
                $lines[$FileLine-1] = sprintf("0 %d # heating_control_function cooling_control_function (in CTL file)\n", $iCoolCtrl);
                
                # Add this system to the new hvac file
                $ThisHVACstop = $FileLine;
                push(@sNewHVAC,@lines[$ThisHVACstart..$ThisHVACstop]); # Add the cooling system to the new hvac file
                
            } elsif($iUnitFunction == 1) { # Heating
                $iThisNumData = 5;
                until(($lines[$FileLine] !~ m/^(#)/) || ($iTHisData == $iThisNumData)) {
                    if ($lines[$FileLine] !~ m/^(#)/) {$iTHisData++;}
                    $FileLine++;
                };
                # Decrement the number of HVAC systems
                $iNewSystems--;
            } else {
                die "setHVACfileDH: Record $house_name, unknown heat pump unit function $iUnitFunction\n";
            }; 

        } else {
            die "setHVACfileDH: Unrecognized HVAC system $iSysType. Should be 1,3 or 7\n";
        };

    
    }; # End of HVAC systems loop
    
    # Update the number of hvac systems
    $sNewHVAC[$iLineTop] = sprintf("%d %.2f # number of systems and altitude (m)\n", $iNewSystems, $fAltitude);
    push(@sNewHVAC,"\n");

    # Print the new hvac file
    PRINT_HVAC: {
        unlink $HVACFile; # Clear old file
        open my $out, '>', $HVACFile or die "Can't write $HVACFile: $!";
        foreach my $ThatData (@sNewHVAC) {
            print $out $ThatData;
        };
        close $out;
    };

    return 1;
};
# ====================================================================
# setDHWfileDH
#       This subroutine removes the dhw system from the .dhw
#       file
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub setDHWfileDH {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $DataLine=0;
    my $iTanks; # Integer holding number of tanks

    # Load the dhw file
    my $DHWFile = $recPath . "$house_name/$house_name.dhw";
    my $fid;
    open $fid, $DHWFile or die "Could not open $DHWFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Load the number of tanks
    $iTanks = $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'Num_Tanks'};
    
    # FFWD over the header data
    until($DataLine == 5) {
        if ($lines[$FileLine] !~ m/^(#)/) {$DataLine++;}
        $FileLine++;
    };

    # Loop through each tank and update the fuel and tank type
    for (my $i=1;$i<=$iTanks;$i++) {
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;} # Zone with tank
        $FileLine++;
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;} # Energy source
        $lines[$FileLine] = sprintf("7 # Fictitious fuel\n");
        $FileLine++;
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;} # Tank type
        $lines[$FileLine] = sprintf("21 # Fictitious tank\n");
        $FileLine++;
        
        my $iSkip = 0;
        
        until(($iSkip == 6) || ($FileLine == ($#lines-1))) {
            if($lines[$FileLine] !~ m/^(#)/) {$iSkip++;}
            $FileLine++;
        };
    };

    # Print the new hvac file
    PRINT_DHW: {
        unlink $DHWFile; # Clear old file
        open my $out, '>', $DHWFile or die "Can't write $DHWFile: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;
    };

    return 1;
};

# Final return value of one to indicate that the perl module is successful
1;