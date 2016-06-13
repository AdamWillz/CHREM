#!/usr/bin/perl

# ====================================================================
# Upgrade_City.pl
# Author: Adam Wills
# Date: Jun 2016

# BASED UPON Hse_Gen.pl
# Author: Lukas Swan
# Date: Oct 2009
# Copyright: Dalhousie University

# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name] [simulation timestep in minutes] [House_list]

# DESCRIPTION:
# This script generates the esp-r house files for each house of the CSDDRD.
# It uses a multithreading approach based on the house type (SD or DR) and 
# region (AT, QC, OT, PR, BC). Which types and regions are generated is 
# specified at the beginning of the script to allow for partial generation.

# The script builds a directory structure for the houses which begins with 
# the house type as top level directories, regions as second level directories 
# and the house name (10 digit w/o ".HDF") inclusing the set_name for each house directory. It places 
# all house files within that directory (all house files in the same directory). 

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

use CSV;	# CSV-2 (for CSV split and join, this works best)
# use Array::Compare;	# Array-Compare-1.15
use threads;	# threads-1.89 (to multithread the program)
use threads::shared;
use File::Path;	# File-Path-2.04 (to create directory trees)
use File::Copy;	# (to copy the input.xml file)
use File::Copy::Recursive qw(fcopy rcopy dircopy fmove rmove dirmove);
use XML::Simple qw(:strict);	# to parse the XML databases for esp-r and for Hse_Gen
use Data::Dumper;	# to dump info to the terminal for debugging purposes
use Switch;
use Storable  qw(dclone);
use Hash::Merge qw(merge);
use POSIX;

use lib qw(./modules);
use General;
use Cross_reference;
use Database;
use Constructions;
use Control;
use Zoning;
use Air_flow;
use BASESIMP;
use Upgrade;
use UpgradeCity;

$Data::Dumper::Sortkeys = \&order;

Hash::Merge::specify_behavior(
	{
		'SCALAR' => {
			'SCALAR' => sub {$_[0] + $_[1]},
			'ARRAY'  => sub {[$_[0], @{$_[1]}]},
			'HASH'   => sub {$_[1]->{$_[0]} = undef},
		},
		'ARRAY' => {
			'SCALAR' => sub {[@{$_[0]}, $_[1]]},
			'ARRAY'  => sub {[@{$_[0]}, @{$_[1]}]},
			'HASH'   => sub {[@{$_[0]}, $_[1]]},
		},
		'HASH' => {
			'SCALAR' => sub {$_[0]->{$_[1]} = undef},
			'ARRAY'  => sub {[@{$_[1]}, $_[0]]},
			'HASH'   => sub {Hash::Merge::_merge_hashes($_[0], $_[1])},
		},
	}, 
	'Merge where scalars are added, and items are (pre)|(ap)pended to arrays', 
);

# --------------------------------------------------------------------
# Declare the global variables
# --------------------------------------------------------------------
my $hse_type;	# String to hold the house type to be processed
my $region;	    # String to hold the region to be simulated
my $set_name;   # Name of the new set
my $setPath;    # String holding path to new set
my $BaseSet;    # Name of the base set being copied
my $Upgrades;   # HASH holding all the upgrade info
my $Surface;    # HASH holding all the surface area data for the community [m2]
my $UPGrecords; # HASH to hold upgrade report data
my @houses_desired = (); # declare an array to store the house names or part of to look
# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+UPG_(.+)_Surfaces.xml/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------
COMMAND_LINE: {
    my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
    my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
	if (@ARGV != 3) {die "Three arguments are required: house_types regions set_name \n";};	# check for proper argument count

	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $BaseSet) = &hse_types_and_regions_and_set_name(shift (@ARGV), shift (@ARGV), shift (@ARGV));
    # Identify this set as an upgrade
	$set_name = '_UPG_' . $BaseSet;

    my $ikeys = 0;
    foreach my $value (values (%{$hse_types})) {
        $hse_type = $value;
        $ikeys++;
    };
    if($ikeys>1) {die "This script only supports only 1 house type at a time\n"};
    $ikeys = 0;
    foreach my $value (values (%{$regions})) {
        $region = $value;
        $ikeys++;
    };
    if($ikeys>1) {die "This script only supports only 1 region at a time\n"};

    # Store the path to the new set
    $setPath="../$hse_type$set_name/$region/";
    
}; # END COMMAND_LINE

# --------------------------------------------------------------------
# Load the upgrade inputs. If there is no upgrades, die
# --------------------------------------------------------------------
$Upgrades = XMLin("../Input_upgrade/Input_All_UPG.xml", keyattr => [], forcearray => 0);

# --------------------------------------------------------------------
# Copy over the base model for upgrades
# --------------------------------------------------------------------
COPY_BASE: {
    my $BCDPath = "../$hse_type". "_$BaseSet/$region/BCD"; # Path to the BCD files
    print "Copying over the base files\n";
    # Get all the house names in the base set
    my $SrcModel = "../$hse_type". "_$BaseSet/$region";
    opendir( my $DIR, $SrcModel );
    while ( my $entry = readdir $DIR ) {
        next unless -d $SrcModel . '/' . $entry;
        next if $entry eq '.' or $entry eq '..';
        next if $entry =~ /BCD/; # Don't copy the BCD files, these tend to be large
        push(@houses_desired,$entry);
    }
    closedir $DIR;
    
    # Create new folder for set
    mkpath($setPath);
    
    foreach my $record (@houses_desired) {
        my $OldPath = "../$hse_type"."_$BaseSet/$region/$record";
        dircopy($OldPath,$setPath . "$record") or die $!;
    };
    
    &setBCDpath(\@houses_desired,$BCDPath,$setPath);
    
    print "Done\n";
}; # END COPY_BASE

# --------------------------------------------------------------------
# Load the surface area data
# --------------------------------------------------------------------
LOAD_SURF: {
    if (defined($possible_set_names->{$BaseSet})) { # Check to see if it is defined in the list
        # Load the surface area data
        my $xmlPath = "../summary_files/UPG_$BaseSet" . "_Surfaces.xml";
        $Surface = XMLin($xmlPath, keyattr => [], forcearray => 0);
        
    }
    else { 
        $Surface = &getGEOdata(\@houses_desired,$setPath);
        my $xmlPath = "../summary_files/UPG_$BaseSet" . "_Surfaces.xml";
        open (my $xmlFID, '>', $xmlPath) or die ("Can't open datafile: $xmlPath");	# open writeable file
        print $xmlFID XMLout($Surface, keyattr => []);	# printout the XML data
        close $xmlFID;
    };
};

# --------------------------------------------------------------------
# Apply upgrade(s) to all eligible dwellings
# --------------------------------------------------------------------
# Open the appropriate CSDDRD file
my $CSDDRDfile = '../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_type . '_subset_' . $region.'.csv';
APPL_UPG: foreach my $house_name (@houses_desired) { # Loop through for each record
    EACH_UPG: foreach my $upg (keys (%{$Upgrades})){
        switch ($upg) {
        
            case "AIM2" {
                print "Inside case AIM2\n";
            }
            case "CEIL_INS" {
                $UPGrecords = &upgradeCeilIns($house_name,$Upgrades->{'CEIL_INS'},$Surface->{"_$house_name"},$setPath,$UPGrecords);
            }
            case "BASE_INS" {
                $UPGrecords = &upgradeBsmtIns($house_name,$Upgrades->{'BASE_INS'},$Surface->{"_$house_name"},$setPath,$UPGrecords);
            }
            case "WALL_INS" {
                print "Inside case WALL_INS\n";
            }
            case "GLZ" {
                print "Inside case GLZ\n";
            }
            case "HRV" {
                print "Inside case HRV\n";
            }
            case "ERV" {
                print "Inside case ERV\n";
            }
            else {print "$upg is not a recognized upgrade. Skipping\n";}
        
        };
    }; # END EACH_UPG

    ## Collect the CSDDRD data for this dwelling
    ## ----------------------------------------------------------------
    #open (my $CSDDRD_fid, '<', $CSDDRDfile) or die ("Can't open datafile: $CSDDRDfile");	# open readable file
    ## cycle through the CSDDRD records to match house record
    #my $CSDDRD;
    #while ($CSDDRD = &one_data_line($CSDDRD_fid, $CSDDRD)) {
    #    if ($CSDDRD->{'file_name'} =~ /^$house_name/) {
    #        # Found corresponding record, stop reading records and jump out of loop
    #        last;
    #    }
    #}
    ## remove the trailing HDF from the house name and check for bad filename
	#$CSDDRD->{'file_name'} =~ s/.HDF$//;

}; # END APPL_UPG

print Dumper $UPGrecords;

