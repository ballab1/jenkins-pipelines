#!/bin/bash

#----------------------------------------------------------------------------
function main()
{
   :> "$JOB_STATUS"

    sudo mount -a
    local dir="${MOUNTPATH%/}"
    local mount="$(mount | grep "$dir" | cut -d ' ' -f 3)"
    if [ "$mount" = "$dir" ]; then
       (timeout --signal=KILL 10 ls -d "$dir") && exit 0
       echo 'STALE MOUNT detected'
       updateStatus 'STALE MOUNT detected'
    else
       echo "${MOUNTPATH} is not mounted"
       updateStatus "${MOUNTPATH} is not mounted"
    fi
    exit 127
}

#----------------------------------------------------------------------------
function onexit()
{
    echo
    if [ -s "$JOB_STATUS" ]; then
      echo '========================================================='
      cat "$JOB_STATUS"
      echo '========================================================='
    fi
    echo
    return 0
}

#----------------------------------------------------------------------------
function updateStatus()
{
    local -r text=${1:?}
    local -r force=${2:-}

    if [ ! -s "$JOB_STATUS" ] || [ "${force:-}" ]; then
        echo "Updating $JOB_STATUS" >&2
        {
            echo 'error.gif'
            echo "$text"
            echo 'FAILED'
         } > "$JOB_STATUS"
    fi
    return 0
}

##########################################################################################################

set -o errtrace
declare -r JOB_STATUS="${1:?}" && shift
declare -r MOUNTPATH="${1:?}"  && shift
export TERM=linux

trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT

main "$@"
