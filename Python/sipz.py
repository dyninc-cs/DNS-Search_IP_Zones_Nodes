#! /usr/bin/env python

''' 
    This script searches and print the zones and nodes related
    to the user's account and the IP address related to the zones 
    and nodes. The user must declare an "A" or "AAAA" when using 
    the node or zone flag. The user can output to a file
    
    The credentials are read out of a configuration file in the 
    same directory name credentials.crg in the format:

    [Dynect]
    user : user_name
    customer : customer_name
    password : password
    
    Usage: %python sipz.py [option]

    Options:
      -h, --help            show this help message and exit
      -i IP, --ip=IP
                            IP Address to search by
      -t RECORD_TYPE, --record_type=RECORD_TYPE
                            Record type to search by
      -n, --node            Search by node
      -z, --zone            Search by zone
      -f FILE, --file=FILE  File to output list to


    The library is available at: 
    https://github.com/dyninc/Dynect-API-Python-Library
'''

import sys
import ConfigParser
from DynectDNS import DynectRest
from optparse import OptionParser

# creating an instance of the api reference library to use
dynect = DynectRest()

def login(cust, user, pwd):
    '''
    This method will do a dynect login

    @param cust: customer name
    @type cust: C{str}

    @param user: user name
    @type user: C{str}

    @param pwd: password
    @type: pwd: C{str}

    @return: the function will exit the script on failure to login
    @rtype: None

    '''

    arguments = {
            'customer_name': cust,
            'user_name': user,
            'password': pwd,
    }

    response = dynect.execute('/Session/', 'POST', arguments)

    if response['status'] != 'success':
        sys.exit("incorrent credentials")
    elif response['status'] == 'success':
        print "Logged Into the DynECT API"

def parseZoneURI(zone_uri):
    '''
    Return back just the zone name from a zone uri

    @param zone_uri: zone uri string
    @type zone_uri: C{str}

    @return: Just the name of the zone
    @rtype: C{str}
    
    '''

    zone_uri = zone_uri.strip('/')
    parts = zone_uri.split('/')
    return parts[len(parts) - 1]

def getNodeList(zone, fqdn=None):
    '''
    This method will return all the nodes for a zone or fqdn

    @param zone: zone name
    @type zone: C{str}

    @param fqdn; fqdn
    @type: C{str}

    @return: List of all nodes in zone
    @rtype: C{list}

    '''

    ending = '/' + zone + '/'

    if fqdn != None:
        ending = ending + fqdn + '/'
    else:
        ending = ending + zone + '/'

    response = dynect.execute('/REST/NodeList' + ending, 'GET')

    if response['status'] != 'success':
        print 'Failed to get nodelist!'
        return None
    nodes = response['data']
    return nodes

def getRecordList(zone, fqdn):
    '''
    This method will return all records for an fqdn

    @param zone: zone name
    @type zone: C{str}

    @param fqdn: fqdn
    @type fqdn: C{str}

    @return: List of all records in a zone
    @rtype: C{list}

    '''

    ending = '/' + zone + '/'

    if fqdn != None:
        ending = ending + fqdn + '/'
    else:
        ending = ending + zone + '/'

    response = dynect.execute('/REST/ANYRecord' + ending, 'GET')

    if response['status'] != 'success':
        print 'Failed to get records!'
        return None
    records = response['data']
    return records

def getRecordData(record_uri):
    '''
    This method will return the data portion of an RR

    @param record_uri: uri of a resource record
    @type record_uri: C{str}

    @return: list of all records in a zone
    @rtype: c{list}

    '''

    response = dynect.execute(record_uri, 'GET')

    if response['status'] != 'success':
        print 'Failed to get record data!'
        return None, None

    data = response['data']

    if "rdata" in data:
        type = data['record_type']
        rdata = data['rdata']
        return type, rdata
    
    return None

def searchZones(match):
    '''
    This method searches for IP addresses that match up with the zone.

    @param match: Name of zone
    @type match: C{str}

    @return: Print the ip addresses relatd to the zone by A or AAAA record

    '''
    
    print '\nYour Zone Search Results:\n'

    response = dynect.execute('/REST/Zone/', 'GET')
    zones = response['data']

    if response['status'] != 'success':
        sys.exit("Could not get Zone Data!")
    
    for zone_uri in zones:
        zone = parseZoneURI(zone_uri)
        nodes = getNodeList(zone)
        print "ZONE: " + zone 
        
        for node in nodes:
            records = getRecordList(zone, node)

            for record in records:

                type, data = getRecordData(record)
                if type == 'A' and match == 'A':
                    print '\t' + data['address']
                elif type == 'AAAA' and match == 'AAAA':
                    print '\t' + data['address']
                    

def searchNodes(match):
    '''
    This method searches for IP addresses that match up with the node.

    @param match: Name of node
    @type match: C{str}

    @return: Print the IP addresses related to the node by A or AAAA record
    @rtype: C{str}

    '''

    print '\nYour Node Search Results:\n'

    response = dynect.execute('/REST/Zone/', 'GET')
    zones = response['data']

    if response['status'] != 'success':
        sys.exit("Could not get Zone Data!")

    for zone_uri in zones:
        zone = parseZoneURI(zone_uri)
        nodes = getNodeList(zone)
        print "ZONE: " + zone 
        for node in nodes:
            print "\tNODE: " + node
            records = getRecordList(zone, node)

            for record in records:

                type, data = getRecordData(record)
                
                if type == 'A' and match == 'A':
                    print '\t\t' + data['address']
                elif type == 'AAAA' and match == 'AAAA':
                    print '\t\t' + data['address']

def searchIP(match, rtype=None):
    '''
    This method searches for zone and nodes by IP Address

    @param match: IP Address to search
    @type match: C{str}

    @return: Print the Zones and Nodes that are related to the IP Address
    @rtype: C{str}

    '''
    
    print '\n'
    print 'Your IP Address Search Results:\n'
    returnList = {}
    returnList['A'] = []
    returnList['AAAA'] = []

    response = dynect.execute('/REST/Zone/', 'GET')
    zones = response['data']

    if response['status'] != 'success':
        sys.exit("Could not get Zone Data!")
        
    
    for zone_uri in zones:
        zone = parseZoneURI(zone_uri)
        nodes = getNodeList(zone)

        for node in nodes:
            records = getRecordList(zone, node)

            for record in records:

                type, data = getRecordData(record)

                if type == 'A' and (type == rtype or rtype == None):
                    if data['address'] == match:
                        returnList['A'].append(node)
                elif type == 'AAAA' and (type == rtype or rtype == None):
                    if data['address'] == match:
                        returnList['AAAA'].append(node)
    
    print 'Here are the results of our search:\n'
    if rtype != None:
        print 'Type ' + rtype + ':'
        for n in returnList[rtype]:
            print '\t' + n
        print '\n'
    else:
        for k, v in returnList.items():
            print 'Type ' + k + ':'
            for n in v:
                print '\t' + n
            print '\n'

usage = "Usage: %python sipz.py [option]"
parser = OptionParser(usage=usage)
parser.add_option("-i", "--ip", dest="ip", help="Ip Address to search by")
parser.add_option("-t", "--record_type", dest="record_type", help="Record type to search by")
parser.add_option("-n", "--node", action="store_true", dest="node", default=False, help="Search by node")
parser.add_option("-z", "--zone", action="store_true", dest="zone", default=False, help="Search by zone")
parser.add_option("-f", "--file", dest="file", help="File to output list to")
(options, args) = parser.parse_args()

#reading in the DynECT user credentials
config = ConfigParser.ConfigParser()

try:
    config.read('credentials.cfg')
except ValueError:
    sys.exit("Error Reading Config file")

try:
    login(config.get('Dynect', 'customer', 'none'),
            config.get('Dynect', 'user', 'none'),
            config.get('Dynect', 'password', 'none'))
except ValueError:
    sys.exit("Error Logging In")

# Validate the right options are being put in.
if options.zone and options.record_type == None:
    parser.error("You must specify an (A or AAAA)")
elif options.node and options.record_type == None:
    parser.error("You must specify an (A or AAAA)")

# Main options list, calls the correct function with the correct parameters to make script run right.
if options.zone and options.record_type == 'A' or options.record_type == 'AAAA':
    searchZones(options.record_type)
elif options.node and options.record_type == 'A' or options.record_type == 'AAAA':
    searchNodes(options.record_type)
elif options.ip:
    searchIP(options.ip)
else:
    sys.exit("You need to define the proper parameters.")

# Log out, to be polite
dynect.execute('/Session/', 'DELETE')
