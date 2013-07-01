#!/usr/bin/perl
#This script searches and print the zones and nodes related
#to the user's account and the IP address related to the zones
#and nodes. The user must declare an "A" or "AAAA" when using
#the node or zone flag. The user can output to a file

#The credentials are read out of a configuration file in the
#same directory name credentials.crg in the format:

#[Dynect]
#user : user_name
#customer : customer_name
#password : password

#Usage: %perl sipz.pl [option]

#Options:
#      -h, --help            Show this help message and exit
#      -i --ip               IP Address to search by
#      -t --type             Record type to search by
#      -n, --node            Search by node
#      -z, --zone            Search by zone
#      -f --file	     File to output list to

#TODO: Better way of printing results AND COMMENTS

use warnings;
use strict;
use Data::Dumper;
use XML::Simple;
use Config::Simple;
use Getopt::Long qw(:config no_ignore_case);
use LWP::UserAgent;
use JSON;
use IO::Handle;

#Get Options
my $opt_zone;
my $opt_node;
my $opt_help;
my $opt_ip;
my $opt_type ="";
my $list;
my $opt_file="";

GetOptions(
	'help' => \$opt_help,
	'ip=s' => \$opt_ip,
	'type=s' => \$opt_type,
	'zones' => \$opt_zone,
	'nodes' => \$opt_node,
	'file=s' =>\$opt_file,
);
$opt_type = uc($opt_type);
if ($opt_type ne "A" && $opt_type ne "AAAA" && $opt_type)
{
	print "Please enter a valid type. Use -t \"A\" or -t \"AAAA\"\n";
	exit;
}
elsif(!$opt_type && ($opt_zone || $opt_node))
{
	print "Please enter a valid type. Use [-n|-z] -t \"A\" or [-n|-z] -t \"AAAA\"\n";
	exit;

}


#Printing help menu
if ($opt_help) {
	print "\t\t-h, --help\t\t Show the help message and exit\n";
	print "\t\t-i, --ip\t\t IP Address to search by\n";
	print "\t\t-t, --record_type\t\t Record type to search by\n";
	print "\t\t-z, --zones\t\t Print the zones\n";
	print "\t\t-n, --nodes\t\t Print the nodes\n";
	print "\t\t-f, --file\t\t File to output\n\n";
	exit;
}

#If the user wants it printed to a file, set standard output to file
if($opt_file ne "")
{
	open OUTPUT, '>', $opt_file or die $!;
	STDOUT->fdopen( \*OUTPUT, 'w' ) or die $!;
}

#Create config reader
my $cfg = new Config::Simple();

# read configuration file (can fail)
$cfg->read('config.cfg') or die $cfg->error();


#dump config variables into hash for later use
my %configopt = $cfg->vars();
my $apicn = $configopt{'cn'} or do {
	print "Customer Name required in config.cfg for API login\n";
	exit;
};

my $apiun = $configopt{'un'} or do {
	print "User Name required in config.cfg for API login\n";
	exit;
};

my $apipw = $configopt{'pw'} or do {
	print "User password required in config.cfg for API login\n";
	exit;
};

#API login
my $session_uri = 'https://api2.dynect.net/REST/Session';
my %api_param = ( 
	'customer_name' => $apicn,
	'user_name' => $apiun,
	'password' => $apipw,
);

#API Login
my $api_request = HTTP::Request->new('POST',$session_uri);
$api_request->header ( 'Content-Type' => 'application/json' );
$api_request->content( to_json( \%api_param ) );

my $api_lwp = LWP::UserAgent->new;
my $api_result = $api_lwp->request( $api_request );

my $api_decode = decode_json ( $api_result->content ) ;
my $api_key = $api_decode->{'data'}->{'token'};


##Set param to empty
%api_param = ();
$session_uri = "https://api2.dynect.net/REST/Zone/";
$api_decode = &api_request($session_uri, 'GET', %api_param);

foreach my $zoneIn (@{$api_decode->{'data'}})
{
	#Getting the zone name out of the response.
	$zoneIn =~ /\/REST\/Zone\/(.*)\/$/;
	my $zone_name = $1;
	%api_param = ();
	print "ZONE: $zone_name\n" unless($opt_ip) ;

	$session_uri = "https://api2.dynect.net/REST/NodeList/$zone_name/";
	$api_decode = &api_request($session_uri, 'GET', %api_param); 
	#Print each node in zone
	foreach my $nodeIn (@{$api_decode->{'data'}})
	{	
		print &getRecordData($zone_name, $nodeIn);
	}
}


#api logout
%api_param = ();
$session_uri = 'https://api2.dynect.net/REST/Session';
&api_request($session_uri, 'DELETE', %api_param); 

sub getRecordData
{
	my($zoneName, $nodeName) = @_;
	##Set param to empty
	%api_param = ();
	$session_uri = "https://api2.dynect.net/REST/ANYRecord/$zoneName/$nodeName/";
	$api_decode = &api_request($session_uri, 'GET', %api_param);
	print "\tNODE: $nodeName\n" unless(!$opt_node);
	my $addresslist ="";	
	foreach my $RecordURI (@{$api_decode->{'data'}})
	{
		$api_decode = &api_request("https://api2.dynect.net$RecordURI", 'GET', %api_param);
		#print Dumper($api_decode);
		my $type =  $api_decode->{'data'}->{'record_type'};
		&display_data($type, $api_decode, $nodeName );
	}
	return $addresslist;
}

sub display_data
{
	my($rec_type, $api_decode, $nodeName) = @_;

	if(($rec_type eq "A" &&  $opt_type eq "A") ||  ($rec_type eq "AAAA" &&  $opt_type eq "AAAA"))
	{
		my $address = $api_decode->{'data'}->{'rdata'}->{'address'};
		print "\t\t$address\n";

	}

	elsif(($rec_type eq "A"  ||  $rec_type eq "AAAA") && $opt_ip)
	{
		my $address = $api_decode->{'data'}->{'rdata'}->{'address'};
		if($address eq $opt_ip)
		{print "\t\t$nodeName\n";}
	}



}

#Accepts Zone URI, Request Type, and Any Parameters
sub api_request{
	#Get in variables, send request, send parameters, get result, decode, display if error
	my ($zone_uri, $req_type, %api_param) = @_;
	$api_request = HTTP::Request->new($req_type, $zone_uri);
	$api_request->header ( 'Content-Type' => 'application/json', 'Auth-Token' => $api_key );
	$api_request->content( to_json( \%api_param ) );
	$api_result = $api_lwp->request($api_request);
	$api_decode = decode_json( $api_result->content);
	$api_decode = &api_fail(\$api_key, $api_decode) unless ($api_decode->{'status'} eq 'success');
	return $api_decode;
}

#Expects 2 variable, first a reference to the API key and second a reference to the decoded JSON response
sub api_fail {
	my ($api_keyref, $api_jsonref) = @_;
	#set up variable that can be used in either logic branch
	my $api_request;
	my $api_result;
	my $api_decode;
	my $api_lwp = LWP::UserAgent->new;
	my $count = 0;
	#loop until the job id comes back as success or program dies
	while ( $api_jsonref->{'status'} ne 'success' ) {
		if ($api_jsonref->{'status'} ne 'incomplete') {
			foreach my $msgref ( @{$api_jsonref->{'msgs'}} ) {
				print "API Error:\n";
				print "\tInfo: $msgref->{'INFO'}\n" if $msgref->{'INFO'};
				print "\tLevel: $msgref->{'LVL'}\n" if $msgref->{'LVL'};
				print "\tError Code: $msgref->{'ERR_CD'}\n" if $msgref->{'ERR_CD'};
				print "\tSource: $msgref->{'SOURCE'}\n" if $msgref->{'SOURCE'};
			};
			#api logout or fail
			$api_request = HTTP::Request->new('DELETE','https://api2.dynect.net/REST/Session');
			$api_request->header ( 'Content-Type' => 'application/json', 'Auth-Token' => $$api_keyref );
			$api_result = $api_lwp->request( $api_request );
			$api_decode = decode_json ( $api_result->content);
			exit;
		}
		else {
			sleep(5);
			my $job_uri = "https://api2.dynect.net/REST/Job/$api_jsonref->{'job_id'}/";
			$api_request = HTTP::Request->new('GET',$job_uri);
			$api_request->header ( 'Content-Type' => 'application/json', 'Auth-Token' => $$api_keyref );
			$api_result = $api_lwp->request( $api_request );
			$api_jsonref = decode_json( $api_result->content );
		}
	}
	$api_jsonref;
}

