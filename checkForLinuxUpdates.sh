#!/bin/bash

set -o errtrace

function extractMsg()
{
    local -r msg="${1:?}"

    local -i start=$( echo "$msg" | grep -nP '^The following ' | cut -d ':' -f 1 )
    local -i end=$( echo "$msg" | grep -nP '^After this' | cut -d ':' -f 1 )
    if [ $end -gt $start ];then
        echo "$msg" | sed -n "$start,$end p"
    fi
    return 0
}

function onexit()
{
    if [ -s "$JOB_STATUS" ]; then
      echo '========================================================='
      cat "$JOB_STATUS"
      echo '========================================================='
    fi
    echo
    echo
    if [ -s "$RESULTS" ]; then
      echo 'show what was done'
      cat "$RESULTS"
    fi
    return 0
}

function latestUpdates()
{
    echo
    echo
    echo 'get latest updates'
    local -i status
    local text

    text="$(sudo /usr/bin/apt-get update -y 2>"$ERRORS")" && status=$? || status=$?
    echo "$text" | tee -a "$RESULTS"
    if [ $status -ne 0 ]; then
        updateStatus "addBadge('error.gif','''${NODENAME}: apt-get update >> ${ERRORS}''')"
        return $status
    fi

    text="$(sudo /usr/bin/apt-get dist-upgrade -y 2>"$ERRORS")" && status=$? || status=$?
    echo "$text" | tee -a "$RESULTS"
    if [ $status -ne 0 ]; then
        updateStatus "addBadge('error.gif','''${NODENAME}: apt-get dist-upgrade >> ${ERRORS}''')"
        return $status
    fi

    if grep -s '*** System restart required ***' <<< "$RESULTS"; then
        updateStatus "addBadge('warning.gif','${NODENAME}: *** System restart required ***')"
        return $status
    fi

    local msg=$(grep -P '\d+ upgraded, \d+ newly installed, \d+ to remove and \d+ not upgraded' <<< "$text" ||:)
    if [ "$msg" ]; then
        local -i changes=$(echo " $msg" | sed 's| and|,|' | awk '{print $0}' RS=',' | awk '{print $1}' | jq -s 'add') ||:
        [ $changes -gt 0 ] && updateStatus "addBadge('completed.gif','''${NODENAME}: $(extractMsg "$text")''')"
    fi
    return 0
}

function main()
{
    [ $(ls -1 *.txt 2>/dev/null|wc -l) > 0 ] && rm *.txt
    [ $(ls -1 "$JOB_STATUS" 2>/dev/null|wc -l) > 0 ] && rm "$JOB_STATUS"
    :> "$RESULTS"
    :> "$JOB_STATUS"

    local -i status=0
    echo "    checking for linux updates on: $(hostname -s)"
    echo "    current directory: $(pwd)"

    removeLocks            || status=$?
    showWhatNeedsDone      || status=$?
    latestUpdates          || status=$?
    report                 || status=$?
    showLinuxVersions      || status=$?
    removeUneededPackages  || status=$?

    [ "$status" -eq 0 ] && rm "$ERRORS"
    return $status
}

function removeLocks()
{
    echo
    echo 'removeLocks'
    local -a pids
    mapfile -t pids < <(ps -efwH | grep '/usr/bin/apt-get' | grep -v 'grep' | awk '{print $2}')
    local pid
    if [ "${#pids[*]}" -gt 0 ]; then
        # kill any old 'apt-get' and remove locks
        sudo kill $(printf '%s ' "${pids[@]}")
        echo 'WARNING: removing old locks'
        sudo rm /var/lib/apt/lists/lock
        sudo rm /var/cache/apt/archives/lock
        sudo rm /var/lib/dpkg/lock*
        updateStatus "addErrorBadge('${NODENAME}: removed locks')"
    fi
}

function removeUneededPackages()
{
    # remove old linux versions
    local -r packages=$(dpkg --get-selections | grep -e 'linux.*-4' | grep -v "$(uname -r | sed s/-generic//)" | awk '{ print  $1 }' | tr '\n' ' ')

    local -i status=0
    if [ "$packages" ]; then
        echo
        echo 'removing OS versions no longer need'
        sudo /usr/bin/apt-get remove -y $packages
        sudo /usr/bin/apt-get purge -y $packages
        status=1
    fi

    if [ "$status" -ne 0 ] || (grep 'sudo apt autoremove' "$RESULTS"); then
        echo
        echo 'removing packages that OS says we no longer need'
        sudo /usr/bin/apt-get autoremove -y
        sudo /usr/bin/apt autoremove -y
    fi
    return 0
}

function report()
{
    echo
    echo
    echo 'report if we need to reboot and/or run fsck'
    local -a checks=('/var/lib/update-notifier/fsck-at-reboot' '/var/run/reboot-required')
    for fl in "${checks[@]}" ; do
        echo "checking $fl"
        [ -s "$fl" ] || continue
        cat "$fl"
        cat "$fl" >> "$RESULTS"
        fl="$(basename "$fl")"
        updateStatus "addWarningBadge('''${NODENAME}: ${fl//-/ }''')"
    done
}

function showLinuxVersions()
{
    echo
    echo
    echo 'report our linux installations'
    dpkg --get-selections | grep 'linux.*-4'
}

function showWhatNeedsDone()
{
    local text
    echo
    echo 'show what needs done'
    /usr/lib/update-notifier/apt-check --human-readable ||:

    text=$(/usr/lib/ubuntu-release-upgrader/check-new-release --check-dist-upgrade-only) || :
    echo "$text"
    local txt=$(grep 'New release' <<< "$text" ||:)
    [ -z "$txt" ] || updateStatus "addBadge('yellow.gif','''${NODENAME}: ${txt}''')"
}

function updateStatus()
{
    local text=${1:?}

    [ -s "$JOB_STATUS" ] || echo "manager.$1" >> "$JOB_STATUS"
}

##########################################################################################################

declare -r NODENAME=${1:-$(hostname -s)}
shift

export TERM=linux
export RESULTS="./${NODENAME}.txt"
export ERRORS="./errors.txt"
export JOB_STATUS=./status.groovy

trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT

main "$@"
