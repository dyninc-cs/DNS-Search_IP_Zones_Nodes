#!/usr/bin/php
<?php
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

#Usage Examples:
#This will go through each zone and node printing out each IPv4 Address
#php -n -t A

#This will go through each zone and node looking for the IP 1.1.1.1 and print the zone when found.
#php -i 1.1.1.1 -t A

#Options:
#      -h, --help            Show this help message and exit
#      -i --ip               IP Address to search by
#      -t --type             Record type to search by
#      -n, --node            Search by node
#      -z, --zone            Search by zone
#      -f --file             File to output list to


#Get options from command line
$shortopts .= "z"; 
$shortopts .= "n"; 
$shortopts .= "f:"; 
$shortopts .= "h"; 
$shortopts .= "i:"; 
$shortopts .= "t:";
$options = getopt($shortopts);

$opt_file .= $options["f"]; 
$opt_ip .= $options["i"]; 
$opt_type .= $options["t"]; 
$opt_type = strtoupper($opt_type);
if (is_bool($options["z"])) {$opt_zone = true;}
if (is_bool($options["n"])) {$opt_node = true;}

#Print help menu
if (is_bool($options["h"])) {
        print "\t\t-h, --help\t\t Show the help message and exit\n";
        print "\t\t-i, --ip\t\t IP Address to search by\n";
        print "\t\t-t, --record_type\t\t Record type to search by\n";
        print "\t\t-z, --zones\t\t Print the zones\n";
        print "\t\t-n, --nodes\t\t Print the nodes\n";
        print "\t\t-f, --file\t\t File to output\n\n";
        exit;	
}
		
#Set the values from file to variables or die
$ini_array = parse_ini_file("config.ini") or die;
$api_cn = $ini_array['cn'] or die("Customer Name required in config.ini for API login\n");
$api_un = $ini_array['un'] or die("User Name required in config.ini for API login\n");
$api_pw = $ini_array['pw'] or die("Password required in config.ini for API login\n");	

# Prevent the user from proceeding if they have not entered -n or -z
if(($opt_zone==true  && $opt_node==true ) || ($opt_zone==true && $opt_node==true))
{
	print "You must enter \"-z\" or \"-n\"\n";
	exit;
}
# Prevent the user from proceeding if they have not entered -t
if($opt_type!="A"  && $opt_type!="AAAA" ) 
{
	print "You must enter \"-t A\" or \"-t AAAA\"\n";
	exit;
}

#Setting file name and opening file for writing if -f is set
if($opt_file != "")
{
	print "Writing file...\n";
	ob_start();
}

#Let the user know what they are searching for if -i
if($opt_ip != "")
	print "Search results for the IP: $opt_ip\n";

# Log into DYNECT
# Create an associative array with the required arguments
$api_params = array(
			'customer_name' => $api_cn,
			'user_name' => $api_un,
			'password' => $api_pw);
$session_uri = 'https://api2.dynect.net/REST/Session/'; 
$decoded_result = api_request($session_uri, 'POST', $api_params,  $token);	

#Set the token
if($decoded_result->status == 'success')
	{$token = $decoded_result->data->token;}
	
$api_params = array (''=> '');
$session_uri = 'https://api2.dynect.net/REST/Zone/'; 
$decoded_result = api_request($session_uri, 'GET', $api_params,  $token);	

# For each zone print the zone name & nodes if requested
foreach($decoded_result->data as $zone_in){

        # Getting ZoneName out of result
        preg_match("/\/REST\/Zone\/(.*)\/$/", $zone_in, $matches);
        $zone_name = $matches[1];

        # Print out each zone
        if($opt_ip == "")
		print "ZONE: ".$zone_name . "\n";

	#Setup API request to get all of the nodes
        $session_uri = 'https://api2.dynect.net/REST/NodeList/'. $zone_name . '/';
        $api_params = array (''=>'');
        $decoded_result = api_request($session_uri, 'GET', $api_params,  $token);
	#Going through each zone.
        foreach($decoded_result->data as $node_in)
	{		
		#If -n is set, print nodes to uesr
		if ($opt_node == true)
			print "\tNODE: $node_in\n";
			
		#Setup API request to get either an A or an AAAA record.
		$api_params = array (''=>'');
		$api_uri = "https://api2.dynect.net/REST/". $opt_type. "Record/$zone_name/$node_in/";
		$api_decode = api_request($api_uri, 'GET', $api_params, $token);
		#Using each records URI for the next request
		foreach ($api_decode->data as $RecordURI)
		{	
			#Getting record type and IP from the response
			$api_decode = api_request("https://api2.dynect.net$RecordURI", 'GET', $api_params, $token);
			$rec_type = $api_decode->data->record_type;
			$address = $api_decode->data->rdata->address;
		
			#If the -i is not set AND the record type matches -t from the command line, and prints the IP
			if($opt_ip == "" && (($rec_type == "A" &&  $opt_type == "A") ||  ($rec_type == "AAAA" &&  $opt_type == "AAAA"))) 
				print "\t\t$address\n";
			
			#If -i is set and -i = the address from the record print the name of the node
			elseif($opt_ip != "" && $opt_ip == $address)
				print "$node_in\n";
		
		}
	}
}


#If -f is set, send the output to the file
if($opt_file != "")
{
	$output = ob_get_contents();
	ob_end_flush();
	$fp = fopen($opt_file,"w");
	fwrite($fp,$output);
	fclose($fp);
	print "\nFile written sucessfully\n";
}

# Logging Out
$session_uri = 'https://api2.dynect.net/REST/Session/'; 
$api_params = array (''=>'');
$decoded_result = api_request($session_uri, 'DELETE', $api_params,  $token);	


# Function that takes zone uri, request type, parameters, and token.
# Returns the decoded result
function api_request($zone_uri, $req_type, $api_params, $token)
{
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);  # TRUE to return the transfer as a string of the return value of curl_exec() instead of outputting it out directly.
	curl_setopt($ch, CURLOPT_FAILONERROR, false); # Do not fail silently. We want a response regardless
	curl_setopt($ch, CURLOPT_HEADER, false); # disables the response header and only returns the response body
	curl_setopt($ch, CURLOPT_HTTPHEADER, array('Content-Type: application/json','Auth-Token: '.$token)); # Set the token and the content type so we know the response format
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $req_type);
	curl_setopt($ch, CURLOPT_URL, $zone_uri); # Where this action is going,
	curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($api_params));

	$http_result = curl_exec($ch);
	$decoded_result = json_decode($http_result); # Decode from JSON as our results are in the same format as our request
	//print_r($decoded_result);	
	if($decoded_result->status != 'success')
	{$decoded_result = api_fail($token, $decoded_result);}  	

	return $decoded_result;
}

#Expects 2 variable, first a reference to the API key and second a reference to the decoded JSON response
function api_fail($token, $api_jsonref) 
{
	#loop until the job id comes back as success or program dies
	while ( $api_jsonref->status != 'success' ) {
		if ($api_jsonref->status != 'incomplete') {
			foreach($api_jsonref->msgs as $msgref) {
				print "API Error:\n";
				print "\tInfo: " . $msgref->INFO . "\n";
				print "\tLevel: " . $msgref->LVL . "\n";
				print "\tError Code: " . $msgref->ERR_CD . "\n";
				print "\tSource: " . $msgref->SOURCE . "\n";
			};
			#api logout or fail
			$session_uri = 'https://api2.dynect.net/REST/Session/'; 
			$api_params = array (''=>'');
			if($token != "")
				$decoded_result = api_request($session_uri, 'DELETE', $api_params,  $token);	
			exit;
		}
		else {
			sleep(5);
			$session_uri = "https://api2.dynect.net/REST/Job/" . $api_jsonref->job_id ."/";
			$api_params = array (''=>'');
			$api_jsonref = api_request($session_uri, 'GET', $api_params,  $token);	
		}
	}
	return $api_jsonref;
}


?>


