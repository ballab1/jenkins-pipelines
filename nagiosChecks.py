#!/usr/bin/python
#  -*- coding: utf-8 -*-

"""
scanShareFiles

    scan a folder and produce JSON stream of attributes foreach file found

See the usage method for more information and examples.

"""
# Imports: native Python
import os
import signal
import psutil
import dnspython as dns
import dns.resolver

# https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/4/en/passivechecks.html
#
# Passive Service Check Results
#    The format of the command is as follows:
#	[<timestamp>] PROCESS_SERVICE_CHECK_RESULT;<host_name>;<svc_description>;<return_code>;<plugin_output>
#    where ...
#  	timestamp is the time in time_t format (seconds since the UNIX epoch) that the service check was perfomed (or submitted). Please note the single space after the right bracket.
#  	host_name is the short name of the host associated with the service in the service definition
#  	svc_description is the description of the service as specified in the service definition
#  	return_code is the return code of the check (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
#  	plugin_output is the text output of the service check (i.e. the plugin output)
#
#Passive Host Check Results
#    The format of the command is as follows:
#	[<timestamp>] PROCESS_HOST_CHECK_RESULT;<host_name>;<host_status>;<plugin_output>
#    where ...
#	timestamp is the time in time_t format (seconds since the UNIX epoch) that the host check was perfomed (or submitted). Please note the single space after the right bracket.
#	host_name is the short name of the host (as defined in the host definition)
#	host_status is the status of the host (0=UP, 1=DOWN, 2=UNREACHABLE)
#	plugin_output is the text output of the host check


#-----------------------------------------------------------------------------
def usage():
    """
        Description:
    """
    examples = """

Usage:
    $progname <folder> <folder> <folder>

"""
    return examples


#-----------------------------------------------------------------------------
class Alarm(Exception):
    pass

def alarm_handler(signum, frame):
    raise Alarm

#-----------------------------------------------------------------------------

class NagiosChecks:

  def __init__(self):
    checkStaleMounts(self)
    checlForZombies(self)
    checkInternetConnectivity(self)

  def findMounts(self):
    mounts = []
    with open('/etc/fstab', mode='rt') as fd:
        for line in fd:
            if re.match(r"^\s*[^#]+(cifs|nfs)", line, re.M):
                fields = re.split('\s', line)
                mounts.append(fields[1])
    return mounts

  def isStale(self, pathToNFSMount):
      signal.signal(signal.SIGALRM, alarm_handler)
      signal.alarm(3)  # 3 seconds
      try:
          proc = subprocess.call('stat '+pathToNFSMount, shell=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE) 
          stdoutdata, stderrdata = proc.communicate()
          signal.alarm(0)  # reset the alarm
          return False
      except Alarm:
          return True


  def checkStaleMounts(self):
    for pathToNFSMount in self.findMounts():
      self.isStale(pathToNFSMount)    


  def checkForZombies(self):
    # cmd: ps faux | awk '{if (match($8, "Z") != 0){ print $0}}'
    proc = subprocess.call('''ps faux | awk '{if (match($8, "Z") != 0){ print $0}}' ''', shell=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE) 
    stdoutdata, stderrdata = proc.communicate()
    zombies = 0
    for proc in psutil.process_iter(['pid', 'name', 'status']):
        if proc.status() == psutil.STATUS_ZOMBIE:
            zombies += 1
    return zombies


  def checkInternetConnectivity(self):
    result = dns.resolver.query('tutorialspoint.com', 'A')


#-----------------------------------------------------------------------------

# ### ----- M A I N   D R I V E R   C O D E ----- ### #

if __name__ == "__main__":
    out = NagiosChecks()
    sys.exit(out.main(sys.argv[1:]))
