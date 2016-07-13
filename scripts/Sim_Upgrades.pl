#!/usr/bin/perl

# ====================================================================
# Sim_Upgrades.pl
# Author: Adam Wills
# Date: Jun 2016

# BASED UPON Sim_Control.pl
# Author: Lukas Swan
# Date: Oct 2009
# Copyright: Dalhousie University

# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name]

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

use Data::Dumper;
use Parallel::ForkManager;

# CHREM modules
use lib ('./modules');
use General;

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name;
my $InputSet;
my $cores;	# store the input core info
my @houses_desired; # declare an array to store the house names or part of to look
my @folders;	#declare an array to store the path to each hse which will be simulated
my $interval; # Number of houses to simulate on each core

my $hse_type_num;
my $region_num;

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 4) {die "A minimum Four arguments are required: house_types regions set_name core_information\n";};
    
	$hse_type_num = shift (@ARGV);
    $region_num = shift (@ARGV);
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name($hse_type_num, $region_num, shift (@ARGV));

	# Check the cores arguement which should be three numeric values seperated by a forward-slash
	unless (shift(@ARGV) =~ /^([1-9]?[0-9])\/([1-9]?[0-9])\/([1-9]?[0-9])$/) {
		die ("CORE argument requires three Positive numeric values seperated by a \"/\": #_of_cores/low_core_#/high_core_#\n");
	};
	
	# set the core information
	# 'num' is total number of cores (if only using a single QC (quad-core) then 8, if using two QCs then 16
	# 'low' is starting core, if using two QCs then the first QC has a 1 and the second QC has a 9
	# 'high' is ending core, value is 8 or 16 depending on machine
	@{$cores}{'num', 'low', 'high'} = ($1, $2, $3);
	
	# check the core infomration for validity
	unless (
		$cores->{'num'} >= 1 &&
		($cores->{'high'} - $cores->{'low'}) >= 0 &&
		($cores->{'high'} - $cores->{'low'}) <= $cores->{'num'} &&
		$cores->{'low'} >= 1 &&
		$cores->{'high'} <= $cores->{'num'}
		) {
		die ("CORE argument numeric values are inappropriate (e.g. high_core > #_of_cores)\n");
	};

	# In case no houses were provided, match everything
	@houses_desired = '.';
    
    # Update the set name
    $InputSet = $set_name;
    $set_name = "_UPG_$set_name";
};

#--------------------------------------------------------------------
# Apply the upgrades to the set
#--------------------------------------------------------------------
APPL_UP:{
    print "Applying Upgrades\n";
    my @PVargs = ("Upgrade_City.pl", "$hse_type_num", "$region_num","$InputSet");
    system($^X, @PVargs);
    print "Done\n";
};

#--------------------------------------------------------------------
# Identify the house folders for simulation
#--------------------------------------------------------------------
FIND_FOLDERS: foreach my $hse_type (&array_order(values %{$hse_types})) {		#each house type
	foreach my $region (&array_order(values %{$regions})) {		#each region
		push (my @dirs, <../$hse_type$set_name/$region/*>);	#read all hse directories and store them in the array
# 		print Dumper @dirs;
		CHECK_FOLDER: foreach my $dir (@dirs) {
			# cycle through the desired house names to see if this house matches. If so continue the house build
			foreach my $desired (@houses_desired) {
				# it matches, so set the flag
				if ($dir =~ /\/$desired/) {
					push (@folders, $dir);
					next CHECK_FOLDER;
				};
			};
		};
	};
}; # END FIND_FOLDERS

#--------------------------------------------------------------------
# Determine how many houses go to each core for core usage balancing
#--------------------------------------------------------------------
$interval = int(@folders/$cores->{'num'}) + 1;	#round up to the nearest integer

#--------------------------------------------------------------------
# Delete old simulation summary files
#--------------------------------------------------------------------
foreach my $file (<../summary_files/*>) { # Loop over the files
	my $check = 'Sim' . $set_name . '_';
	if ($file =~ /$check/) {unlink $file;};
};

#--------------------------------------------------------------------
# Generate and print lists of directory paths for each core to simulate
#--------------------------------------------------------------------
SIMULATION_LIST: {
	foreach my $core (1..$cores->{'num'}) {
		my $low_element = ($core - 1) * $interval;	#hse to start this particular core at
		my $high_element = $core * $interval - 1;	#hse to end this particular core at
		if ($core == $cores->{'num'}) { $high_element = $#folders};	#if the final core then adjust to end of array to account for rounding process
		my $file = '../summary_files/Sim' . $set_name . '_House-List_Core-' . $core . '.csv';
		open (HSE_LIST, '>', $file) or die ("can't open $file");	#open the file to print the list for the core
		foreach my $element ($low_element..$high_element) {
			if (defined($folders[$element])) {
				print HSE_LIST "$folders[$element]\n";	#print the hse path to the list
			};
		}
		close HSE_LIST;		#close the particular core list
	};
};

#--------------------------------------------------------------------
# Call the simulations.
#--------------------------------------------------------------------
SIMULATION_1: {
    print "Multithreading the ESP-r simulations\n";
    my $n_processes = $cores->{'num'};
    my $pm = Parallel::ForkManager->new( $n_processes );
	foreach my $core ($cores->{'low'}..$cores->{'high'}) {	#simulate the appropriate list (i.e. QC2 goes from 9 to 16)
		my $file = '../summary_files/Sim' . $set_name . '_Core-Output_Core-' . $core . '.txt';
        $pm->start and next;
		system ("./Core_Sim.pl $core $set_name > $file");	#pass the argument $core so the program knows which set to simulate
        $pm->finish;
	}
    $pm->wait_all_children;
	print "THE SIMULATION OUTPUTS FOR EACH CORE ARE LOCATED IN ../summary_files/\n";
};

#--------------------------------------------------------------------
# TODO: Post-process and save the data
#--------------------------------------------------------------------

#--------------------------------------------------------------------
# Call the simulations again to retrieve the timestep reports
#--------------------------------------------------------------------
SIMULATION_2: {
    # Run the timestep modifier
    my @PVargs = ("Timestep.pl", "$hse_type_num", "$region_num","$InputSet","0");
    system($^X, @PVargs);
    
    my $n_processes = $cores->{'num'};
    my $pm = Parallel::ForkManager->new( $n_processes );
	foreach my $core ($cores->{'low'}..$cores->{'high'}) {	#simulate the appropriate list (i.e. QC2 goes from 9 to 16)
		my $file = '../summary_files/Sim' . $set_name . '_Core-Output_Core-' . $core . '.txt';
        $pm->start and next;
		system ("./Core_Sim.pl $core $set_name > $file");	#call nohup of simulation program script and pass the argument $core so the program knows which set to simulate
        $pm->finish;
	}
    $pm->wait_all_children;
	print "THE SIMULATION OUTPUTS FOR EACH CORE ARE LOCATED IN ../summary_files/\n";
};

#--------------------------------------------------------------------
# TODO: Post-process and save the data
#--------------------------------------------------------------------

#--------------------------------------------------------------------
# TODO: Call TRNSYS simulation
#--------------------------------------------------------------------

#--------------------------------------------------------------------
# TODO: Post-process and report performance metrics
#--------------------------------------------------------------------