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
my @houses_desired; # declare an array to store the house names or part of to look

# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Sim_(.+)_Sim-Status.+/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 3) {die "A minimum three arguments are required: house_types regions set_name [house names]\nPossible set_names are: @possible_set_names_print\n";};
	
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift(@ARGV), shift(@ARGV), shift(@ARGV));

	# Verify the provided set_name
	if (defined($possible_set_names->{$set_name})) { # Check to see if it is defined in the list
		$set_name =  '_' . $set_name; # Add and underscore to the start to support subsequent code
	}
	else { # An inappropriate set_name was provided so die and leave a message
		die "Set_name \"$set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
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
	my $check = 'Community' . $set_name . '_';
	if ($file =~ /$check/) {unlink $file;};
};

#--------------------------------------------------------------------
# Multithread to aquire the xml results faster, merge then print them out to csv files
#--------------------------------------------------------------------
MULTITHREAD_RESULTS: {

    # Determine import/export of community
	my @Tstep = &collect_results_data(@folders);

	# Sort and pass data
	&SortMonRep(@Tstep);
	
	my $localtime = localtime(time);
	print "Set: $set_name; End Time: $localtime\n";
};

#--------------------------------------------------------------------
# Subroutine to collect the XML data
#--------------------------------------------------------------------
sub collect_results_data {
    my @folders = @_;
	
	#--------------------------------------------------------------------
	# Cycle through the data and collect the results
	#--------------------------------------------------------------------
    
    # Create an energy results hash reference to store accumulated data
    my $results_all;
    my @net = (); # Timestep 

	# Cycle over each folder
	FOLDER: foreach my $folder (@folders) {
		
        my ($hse_type, $region, $hse_name) = ($folder =~ /^\.\.\/(\d-\w{2}).+\/(\d-\w{2})\/(.+)$/);
        my $file = $folder . "/out.csv";
        my @Tdata = ();

        # Examine the directory and see if a results file (house_name.xml) exists. If it does than we had a successful simulation. If it does not, go on to the next house.
		unless (grep(/$out.xml$/, <$folder/*>)) {
			# Store the house name so we no it is bad - with a note
			$results_all->{'bad_houses'}->{$region}->{$hse_type}->{$hse_name} = 'Missing the XML file';
            print "Problem with $hse_name out.csv\n"
			next FOLDER;  # Jump to the next house if it does not return a true.
		};
        
        # Open the timestep file
        my $iPass=0;
        open(my $data, '<', $file) or die "Could not open '$file' $!\n";

        while (my $line = <$data>) {
            if ($iPass < 1) { # Skip the header
                $iPass = 1;
            } else {
                chomp $line;
                my @fields = split "," , $line;
                my $sum = $fields[0]-$fields[1]; # Negative=import, Positive=export
                push(@Tdata, $sum);
            };
        };
        # Update community use
        for ($i=0;$i<scalar @Tdata;$i++){
            if (@net) {
                $net[$i] = $net[$i] + $Tdata[$i];
            } else {
                push(@net, $Tdata[$i]);
            };
        };        
        
	};
	
	return (@net);
};

#--------------------------------------------------------------------
# Subroutine to print out the site balance data
#--------------------------------------------------------------------
sub SortMonRep {

    my @net = @_;
    
    #print Dumper @net;
    
    my $file = "../summary_files/Community$set_name" . ".csv";
    
    # TODO: Array with indexes for day of the year
    
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

