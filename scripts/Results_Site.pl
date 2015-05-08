#!/usr/bin/perl
# 
#====================================================================
# Results2.pl
# Author:    Lukas Swan
# Date:      Apr 2010
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] set_name [cores/start_core/end_core]
# Use start and end cores to evenly divide the houses between two machines (e.g. QC2 would be [16/9/16]) [house names that are the only desired]
#
# DESCRIPTION:
# This script aquires results


#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;

use CSV; #CSV-2 (for CSV split and join, this works best)
#use Array::Compare; #Array-Compare-1.15
#use Switch;
use XML::Simple; # to parse the XML results files
use XML::Dumper;
use threads; #threads-1.71 (to multithread the program)
#use File::Path; #File-Path-2.04 (to create directory trees)
#use File::Copy; #(to copy files)
use Data::Dumper; # For debugging
use Storable  qw(dclone); # To create copies of arrays so that grep can do find/replace without affecting the original data
use Hash::Merge qw(merge); # To merge the results data

# CHREM modules
use lib ('./modules');
use General; # Access to general CHREM items (input and ordering)
use Results; # Subroutines for results accumulations
use XML_reporting; # Sorting functionality for the house xml results reporting

# Set Data Dumper to report in an ordered fashion
$Data::Dumper::Sortkeys = \&order;

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my $hse_types; # declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions; # declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name; # store the results set name
my $cores; # store the input core info
my @houses_desired; # declare an array to store the house names or part of to look
my $mode;

# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Sim_(.+)_Sim-Status.+/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 5) {die "A minimum Four arguments are required: house_types regions set_name core_information mode [house names]\nPossible set_names are: @possible_set_names_print\n";};
	
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift(@ARGV), shift(@ARGV), shift(@ARGV));

	# Verify the provided set_name
	if (defined($possible_set_names->{$set_name})) { # Check to see if it is defined in the list
		$set_name =  '_' . $set_name; # Add and underscore to the start to support subsequent code
	}
	else { # An inappropriate set_name was provided so die and leave a message
		die "Set_name \"$set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
	};

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
    
    $mode = shift;
    if ($mode < 0 || $mode > 2) {
        die ("Results mode but be between 0 and 2\nMode 0: Only consider CHREM T and D losses\nMode 1: EnergyStar source energy factors\nMode 2: NREL source energy factors");
    };

	# Provide support to only simulate some houses
	@houses_desired = @ARGV;
	# In case no houses were provided, match everything
	if (@houses_desired == 0) {@houses_desired = '.'};
	
	my $localtime = localtime(time);
	print "Set: $set_name; Start Time: $localtime\n";
};

#--------------------------------------------------------------------
# Identify the house folders for results aquisition
#--------------------------------------------------------------------
my @folders;	#declare an array to store the path to each hse which will be simulated

foreach my $hse_type (&array_order(values %{$hse_types})) {		#each house type
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
};


#--------------------------------------------------------------------
# Delete old summary files
#--------------------------------------------------------------------
foreach my $file (<../summary_files/*>) { # Loop over the files
	my $check = 'SiteBal' . $set_name . '_';
	if ($file =~ /$check/) {unlink $file;};
    $check = 'SrcBal' . $set_name . '_';
	if ($file =~ /$check/) {unlink $file;};
};


#--------------------------------------------------------------------
# Determine how many houses go to each core for core usage balancing
#--------------------------------------------------------------------
my $interval = int(@folders/$cores->{'num'}) + 1;	#round up to the nearest integer



#--------------------------------------------------------------------
# Multithread to aquire the xml results faster, merge then print them out to csv files
#--------------------------------------------------------------------
MULTITHREAD_RESULTS: {

	my $thread; # Declare threads for each core
	
	foreach my $core (1..$cores->{'num'}) { # Cycle over the cores
		if ($core >= $cores->{'low'} && $core <= $cores->{'high'}) { # Only operate if this is a desireable core
			my $low_element = ($core - 1) * $interval; # Hse to start this particular core at
			my $high_element = $core * $interval - 1; # Hse to end this particular core at
			if ($core == $cores->{'num'}) { $high_element = $#folders}; # If the final core then adjust to end of array to account for rounding process

			$thread->{$core} = threads->new(\&collect_results_data, @folders[$low_element..$high_element], $mode); # Spawn the threads and send to subroutine, supply the folders
		};
	};

	my $results_all = {}; # Declare a storage variable
	
	foreach my $core (1..$cores->{'num'}) { # Cycle over the cores
		if ($core >= $cores->{'low'} && $core <= $cores->{'high'}) { # Only operate if this is a desireable core
			$results_all = merge($results_all, $thread->{$core}->join()); # Return the threads together for info collation using the merge function
		};
	};
	
	# Call the remaining results printout and pass the results_all
	&SiteBalanceRep($results_all, $set_name);
	
	my $localtime = localtime(time);
	print "Set: $set_name; End Time: $localtime\n";
};

#--------------------------------------------------------------------
# Subroutine to collect the XML data
#--------------------------------------------------------------------
sub collect_results_data {
    my @folders = @_;
    my $mode = pop @folders;
	
	#--------------------------------------------------------------------
	# Cycle through the data and collect the results
	#--------------------------------------------------------------------

	# Declare and fill out a set out formats for values with particular units
	my $units = {};
	@{$units}{qw(GJ W kg kWh l m3 tonne COP)} = qw(%.1f %.0f %.0f %.0f %.0f %.0f %.3f %.2f);
    
    my $ghg_file;
	if (-e '../../../keys/GHG_key.xml') {$ghg_file = '../../../keys/GHG_key.xml'}
	elsif (-e '../keys/GHG_key.xml') {$ghg_file = '../keys/GHG_key.xml'}
	my $GHG = XMLin($ghg_file);
    # Remove the 'en_src' field
	my $en_srcs = $GHG->{'en_src'};
    
    # Create an energy results hash reference to store accumulated data
    my $results_all;

	# Cycle over each folder
	FOLDER: foreach my $folder (@folders) {
		# Determine the house type, region, and hse_name
		my ($hse_type, $region, $hse_name) = ($folder =~ /^\.\.\/(\d-\w{2}).+\/(\d-\w{2})\/(.+)$/);
        $results_all->{$hse_name}->{'hse_type'} = $hse_type;
        $results_all->{$hse_name}->{'region'} = $region;
        $results_all->{$hse_name}->{'parameter'} = {};
        
        my $Output = $results_all->{$hse_name}->{'parameter'};
        my $site_ghg;
        
        

		# Store the coordinate information for error reporting
		my $coordinates = {'hse_type' => $hse_type, 'region' => $region, 'file_name' => $hse_name};

		# Open the site balance data for electricity
        my $XML = XMLin("$folder/$hse_name.xml");
        # Remove the 'parameter' field
        my $parameters = $XML->{'parameter'};
        
        my @FF=();
        # Pull all the src data for site that isn't electricity
        foreach my $key (keys %{$parameters}) {
            if ($key =~ /^CHREM\/SCD\/src\/(\w+)\/energy$/) {
                my $src = $1;
                push(@FF, $src);
                unless ($src =~ /electricity/) {
                    foreach my $period (@{&order($parameters->{$key}, [], [qw(units description)])}) {

                        # Determine source energy factor (SEF) to use
                        my $SEF = 1;
                        if ($mode == 1 ) { # EnergyStar source factors
                            $SEF = $en_srcs->{$src}->{'ESource'};
                        } elsif ($mode == 2) { # NREL
                            $SEF = $en_srcs->{$src}->{'NREL'}->{'NSource'};
                        };

                        # Store the source energy for this period
                        $Output->{"CHREM/Site_Bal/src/$src/energy"}->{$period}->{'site'}=$parameters->{$key}->{$period}->{'integrated'};
                        $Output->{"CHREM/Site_Bal/src/$src/energy"}->{$period}->{'source'}=$parameters->{$key}->{$period}->{'integrated'}*$SEF;
                        $Output->{"CHREM/Site_Bal/src/$src/energy"}->{'units'}=$parameters->{$key}->{'units'}->{'integrated'};
                        
                        # Determine method to for GHG calculation
                        $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{'units'} = 'kg';
                        if ($mode < 2) { # Use the CHREM method
                            $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'site'} = $parameters->{"CHREM/SCD/src/$src/quantity"}->{$period}->{'integrated'} * $en_srcs->{$src}->{'GHGIF'} / 1000;
                            $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'source'} = $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'site'};
                            
                        } else { # Using factors from NREL
                            $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'site'} = $parameters->{"CHREM/SCD/src/$src/quantity"}->{$period}->{'integrated'} * $en_srcs->{$src}->{'NREL'}->{'siteCombGHGIF'} / 1000;
                            $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'pre'} = $parameters->{"CHREM/SCD/src/$src/quantity"}->{$period}->{'integrated'} * $en_srcs->{$src}->{'NREL'}->{'preCombGHGIF'} / 1000;
                            $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'source'} = $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'site'} + $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'pre'};
                        };
                        unless (defined($site_ghg->{$period})) {$site_ghg->{$period} = 0;};
                        # Update the site GHG
                        $site_ghg->{$period} = $site_ghg->{$period} + $Output->{"CHREM/Site_Bal/src/$src/GHG"}->{$period}->{'source'};
                    };
                };
            };
		};
        # Pull the grid data
        my $per_sum = 0;
        my $import = 'CHREM/Site_Bal/NodeBalance/V_node_1/net_import';
        $Output->{$import}->{'units'} = $parameters->{$import}->{'units'}->{'integrated'};
        $Output->{"CHREM/Site_Bal/src/electricity/GHG"}->{'units'} = 'kg';
		foreach my $period (@{&order($parameters->{$import}, [], [qw(units P00 description)])}) {
			my $mult;
            # Site electricity import
            $Output->{$import}->{$period}->{'site'} = $parameters->{$import}->{$period}->{'integrated'};
            
            if ($mode < 2) {
                if (defined($en_srcs->{'electricity'}->{'province'}->{$XML->{'province'}}->{'period'}->{$period}->{'GHGIFavg'})) {
                    $mult = $en_srcs->{'electricity'}->{'province'}->{$XML->{'province'}}->{'period'}->{$period}->{'GHGIFavg'};
                }
                else {
                    $mult = $en_srcs->{'electricity'}->{'province'}->{$XML->{'province'}}->{'period'}->{'P00_Period'}->{'GHGIFavg'};
                };
                
                if ($mode == 1) { # EnergyStar source factor
                    $Output->{$import}->{$period}->{'source'} = $parameters->{$import}->{$period}->{'integrated'}*$en_srcs->{'electricity'}->{'province'}->{$XML->{'province'}}->{'period'}->{'P00_Period'}->{'ESsource'};
                } else {
                    $Output->{$import}->{$period}->{'source'} = $Output->{$import}->{$period}->{'site'};
                }; 
                
                $Output->{"CHREM/Site_Bal/src/electricity/GHG"}->{$period}->{'source'} = $parameters->{$import}->{$period}->{'integrated'} / (1 - $en_srcs->{'electricity'}->{'province'}->{$XML->{'province'}}->{'trans_dist_loss'}) * $mult / 1000;

           } elsif ($mode == 2) { # EnergyStar method
                $mult = $en_srcs->{'electricity'}->{'province'}->{$XML->{'province'}}->{'period'}->{'P00_Period'}->{'NGHGIFavg'};
                # Source energy
                $Output->{$import}->{$period}->{'source'} = $Output->{$import}->{$period}->{'site'} * $en_srcs->{'electricity'}->{'province'}->{$XML->{'province'}}->{'period'}->{'P00_Period'}->{'NSource'};
                
                $Output->{"CHREM/Site_Bal/src/electricity/GHG"}->{$period}->{'source'} = $Output->{$import}->{$period}->{'source'} * $mult / 1000;
           };
           
           unless (defined($site_ghg->{$period})) {$site_ghg->{$period} = 0;};
           $site_ghg->{$period} = $site_ghg->{$period} + $Output->{"CHREM/Site_Bal/src/electricity/GHG"}->{$period}->{'source'};
           $per_sum = $per_sum + $Output->{"CHREM/Site_Bal/src/electricity/GHG"}->{$period}->{'source'};

		};
		$Output->{"CHREM/Site_Bal/src/electricity/GHG"}->{'P00_Period'}->{'source'} = $per_sum;
		unless (defined($site_ghg->{'P00_Period'})) {$site_ghg->{'P00_Period'} = 0;};
		$site_ghg->{'P00_Period'} = $site_ghg->{'P00_Period'} + $Output->{"CHREM/Site_Bal/src/electricity/GHG"}->{'P00_Period'}->{'source'};
        
        
        # Pull the exported to grid data
        $import = 'CHREM/Site_Bal/NodeBalance/V_node_1/net_export';
        $Output->{$import}->{'units'} = $parameters->{$import}->{'units'}->{'integrated'};
		foreach my $period (@{&order($parameters->{$import}, [], [qw(units P00 description)])}) {
            $Output->{$import}->{$period}->{'site'} = $parameters->{$import}->{$period}->{'integrated'};
		};
        
	};
	
	return ($results_all);
};

#--------------------------------------------------------------------
# Subroutine to print out the site balance data
#--------------------------------------------------------------------
sub SiteBalanceRep {

    my $results_all=shift; 
    my $set_name=shift;
    
    #print Dumper $results_all;
    
    my $fileSiteBal = "../summary_files/SiteBal$set_name" . ".csv";
    my @SiteBal=();
    my $fileSrcBal = "../summary_files/SrcBal$set_name" . ".csv";
    my @SrcBal=();
    
    # Local strings
    my $header = "house,type,province,";
    my @Mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my @Per = ();
    my $i=1;
    foreach my $m (@Mon) {
        my $ins = sprintf("%02s", $i);
        push(@Per, ("P$ins" . "_$m"));
        $i++;
    };
    push(@Per, 'P00_Period');
    push(@Mon, 'Ann');
    my @FF=('natural_gas','propane','oil');

    my @Sitekeys = ("CHREM/Site_Bal/NodeBalance/V_node_1/net_export","CHREM/Site_Bal/NodeBalance/V_node_1/net_import");
    my @labels=(",,,Elec_export [GJ],,,,,,,,,,,,,Elec_import [GJ],,,,,,,,,,,,,");
    push(@labels, "house,type,province,");   
    foreach my $ff (@FF) {
        push(@Sitekeys, "CHREM/Site_Bal/src/$ff/energy");
        $labels[0] = $labels[0] . "$ff" ."_import [GJ],,,,,,,,,,,,,";
    };
    $labels[0] = $labels[0] . "\n";
     
    for (my $i=1;$i<=(3+$#FF);$i++) {
        foreach my $mark (@Mon) {
            $labels[1] = $labels[1] . "$mark,";
        };
    };
    $labels[1] = $labels[1] . "\n";
    push(@SiteBal, @labels);
    push(@SrcBal, @labels);
    
    # Begin looping through data
    foreach my $hse_name (keys %{$results_all}) {
        my $type = $results_all->{$hse_name}->{'hse_type'};
        my $region = $results_all->{$hse_name}->{'region'};
        my $parameter = $results_all->{$hse_name}->{'parameter'};
        
        my $Siteline = "$hse_name,$type,$region,";
        my $Srcline = $Siteline;
        
        foreach my $keylog (@Sitekeys) {
            foreach my $period (@Per) {
                my $data;
                if (defined $parameter->{$keylog}->{$period}->{'source'}) {
                    $data = $parameter->{$keylog}->{$period}->{'source'};
                } else {
                    $data = "0";
                };
                $Srcline = $Srcline . "$data,";
                
                if (defined $parameter->{$keylog}->{$period}->{'site'}) {
                    $data = $parameter->{$keylog}->{$period}->{'site'};
                } else {
                    $data = "0";
                };
                $Siteline = $Siteline . "$data,";

            };
        };
        $Srcline = $Srcline . "\n";
        $Siteline = $Siteline . "\n";
        push(@SiteBal, $Siteline);
        push(@SrcBal, $Srcline);

    };
    
    # pass the output
	open (my $FILE, '>', $fileSiteBal) or die ("\n\nERROR: can't open $fileSiteBal\n");
    print $FILE @SiteBal;
    close($fileSiteBal);
    
    open ($FILE, '>', $fileSrcBal) or die ("\n\nERROR: can't open $fileSrcBal\n");
    print $FILE @SrcBal;
    close($fileSrcBal);

    return(1);
};

