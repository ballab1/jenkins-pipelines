#!/bin/bash


#----------------------------------------------------------------------------
function main()
{
   :> "$JOB_STATUS"

    sudo mount -a
    local mount="$(mount | grep "$MOUNTPATH" | cut -d ' ' -f 3)"
    if [ "$mount" = "$MOUNTPATH" ]; then
      (timeout --signal=KILL 10 ls -d "$MOUNTPATH") && return 0
       updateStatus 'STALE MOUNT detected'
    else
       updateStatus "${MOUNTPATH} is not mounted" 
    fi
    exit 127
}

#----------------------------------------------------------------------------
function onexit()
{
    echo
    echo
    if [ -s "$JOB_STATUS" ]; then
      echo '========================================================='
      cat "$JOB_STATUS"
      echo '========================================================='
    fi
    return 0
}
 
#----------------------------------------------------------------------------
function updateStatus()
{
    local -r text=${1:?}

    [ -z "${text:-}" ] && return 0
    [ -s "$JOB_STATUS" ] || return 0

    echo "manager.$text"; echo "currentBuild.result = 'FAILED'" > "$JOB_STATUS"
}

##########################################################################################################

set -o errtrace
declare -r MOUNTPATH="${1:?}"

export TERM=linux
export JOB_STATUS=./status.groovy

trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT

main
