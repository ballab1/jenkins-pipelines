#!/bin/bash -x

#=============================================================================== 
#
#  realUptime:  calculate 'uptime' based on timestamp of /proc/1
#               this gives us correct uptime for containers
#
#=============================================================================== 
function procOneUptime()
{
    local -i seconds="$(( $(date +%s) - $(stat -c %Z /proc/1) ))"
    local -r days=$(( seconds/86400 ))
    seconds=$(( seconds - (days*86400) ))

    local -r hours=$(( seconds/3600 ))
    seconds=$(( seconds - (hours*3600) ))

    local -r minutes=$(( seconds/60 ))
#    seconds=$(( seconds - (minutes*60) ))

#    echo -n "${days} days, ${hours}:${minutes}:${seconds}"
    echo -n "${days} days, ${hours}:${minutes}"

}

#=============================================================================== 

if [ $( grep -c 'docker' /proc/1/cgroup ) -ne 0 ]; then

    uptime | sed -E -e "s|[0-9]+\s+day,\s+[0-9]+:[0-9]+,|$( procOneUptime ),|"

else
    uptime
fi    
