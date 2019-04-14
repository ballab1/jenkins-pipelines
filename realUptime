#!/bin/bash
#=============================================================================== 
#
#  realUptime:  calculate 'uptime' based on timestamp of /proc/1
#               this gives us correct uptime for containers
#
#=============================================================================== 
function procOneUptime()
{
    expr $(date +%s) - $(stat -c %Z /proc/1) 
}

#=============================================================================== 
function realUptime()
{
    local up=$( uptime )
    local ts="${up:1:12}"

    # remove content befor 1st two commas
    up="${up#*,}"
    up="${up#*,}"

    # reconstruct uptime string with value calculated from '/proc/1'
    printf " %s %s, %s" "$ts" "$( secondsToDaysHoursMinutesSeconds $( procOneUptime ) )" "$up"
}

#=============================================================================== 
function secondsToDaysHoursMinutesSeconds()
{
    local seconds=$1
    local days=$(($seconds/86400))
    seconds=$(($seconds-($days*86400) ))

    local hours=$(($seconds/3600))
    seconds=$((seconds-($hours*3600) ))

    local minutes=$(($seconds/60))
    seconds=$(( $seconds-($minutes*60) ))

    echo -n "${days} days, ${hours}:${minutes}:${seconds}"
}

#=============================================================================== 

if [ $( grep -c 'docker' /proc/1/cgroup ) -eq 0 ]; then
    uptime
else
    realUptime
fi    
