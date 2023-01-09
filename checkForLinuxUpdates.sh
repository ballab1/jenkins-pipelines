#!/bin/bash

#----------------------------------------------------------------------------
function extractMsg()
{
    local -r msg="${1:?}"

    local -a data

    mapfile -t data < <( echo "$msg" | grep -nP '^The following ' | cut -d ':' -f 1 )
    if [ "${#data[*]}" -eq 0 ]; then
        echo "$msg"
        return 0
    fi

    local -i start="${data[0]}"
    mapfile -t data < <( echo "$msg" | grep -nP '^After this' | cut -d ':' -f 1 )
    if [ "${#data[*]}" -eq 0 ]; then
        echo "$msg"
        return 0
    fi

    local -i end="${data[0]}"
    if [ "$end" -gt "$start" ]; then
        echo "$msg" | sed -n "$start,$end p"
    else
        echo "$msg"
    fi
    return 0
}

#----------------------------------------------------------------------------
function latestUpdates()
{
    echo
    echo
    echo 'Get latest updates'
    local -i status
    local text

    echo
    echo "sudo /usr/bin/apt-get update -y"
    text="$(sudo /usr/bin/apt-get update -y 2>"$ERRORS")" && status=$? || status=$?
    echo "$text"
    if [ $status -ne 0 ]; then
        updateStatus "addBadge('error.gif','''${NODENAME}: apt-get update >> ${ERRORS}''')"
        return $status
    fi

    echo
    echo "sudo /usr/bin/apt-get dist-upgrade -y"
    text="$(sudo /usr/bin/apt-get dist-upgrade -y 2>"$ERRORS")" && status=$? || status=$?
    # sudo apt-get --with-new-pkgs upgrade"
    echo "$text"
    if [ $status -ne 0 ]; then
        updateStatus "addBadge('error.gif','''${NODENAME}: apt-get dist-upgrade >> ${ERRORS}''')"
        return $status
    fi

    # shellcheck disable=SC2086,SC2155
    local msg=$(grep -P '\d+ upgraded, \d+ newly installed, \d+ to remove and \d+ not upgraded' <<< "$text" ||:)
    if [ "$msg" ]; then
         # shellcheck disable=SC2086,SC2155
        local -i changes=$(echo " $msg" | sed 's| and|,|' | awk '{print $0}' RS=',' | awk '{print $1}' | jq -s 'add') ||:
        if [ "$changes" -gt 0 ]; then
           msg="$(extractMsg "$msg")"
           [ "$msg" ] && updateStatus "addBadge('completed.gif','''${NODENAME}: ${msg}''')"
        fi
    fi

    # shellcheck disable=SC2063
    if grep -s '*** System restart required ***' <<< "$text"; then
        :> "$JOB_STATUS"
        updateStatus "addBadge('warning.gif','${NODENAME}: *** System restart required ***')"
        return $status
    fi

    echo
    echo "sudo /usr/bin/apt autoremove -y"
    sudo /usr/bin/apt autoremove -y &>/dev/null
    return 0
}

#----------------------------------------------------------------------------
function main()
{
    [ -e "$JOB_STATUS" ] && sudo rm "$JOB_STATUS"
    :> "$JOB_STATUS"

    local -i status=0
    echo "    Checking for linux updates on: $(hostname -s)"
    echo "    current directory: $(pwd)"

    if [ "$(hostname -s)" = 'pi' ]; then
        echo "sudo apt update"
        sudo apt update
        # shellcheck disable=SC2086,SC2155
        local updates="$(sudo apt list --upgradable)"
        if [ "$(echo "$updates:-}" | wc -l)" -gt 1 ];then
# need to look for 'you should consider rebooting.'        
            echo "sudo apt full-upgrade -y"
            sudo apt full-upgrade -y
            echo "sudo apt autoremove"
            sudo apt autoremove
            echo "sudo apt clean"
            sudo apt clean
        fi
    else
        removeLocks            || status=$?
        showWhatNeedsDone      || status=$?
        latestUpdates          || status=$?
        report                 || status=$?
        showLinuxVersions      || status=$?
        removeUneededPackages  || status=$?
    fi

    [ "$status" -eq 0 ] && rm "$ERRORS"
    return $status
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
function removeLocks()
{
    echo
    echo 'RemoveLocks'
    local -a pids
    # shellcheck disable=SC2009
    mapfile -t pids < <(ps -efwH | grep '/usr/bin/apt-get' | grep -v 'grep' | awk '{print $2}')
    if [ "${#pids[*]}" -gt 0 ]; then
        # kill any old 'apt-get' and remove locks
        echo
        echo "kill $(printf '%s ' "${pids[@]}")"
        # shellcheck disable=SC2046
        sudo kill $(printf '%s ' "${pids[@]}")
        echo 'WARNING: removing old locks'
        sudo rm /var/lib/apt/lists/lock
        sudo rm /var/cache/apt/archives/lock
        sudo rm /var/lib/dpkg/lock*
        updateStatus "addErrorBadge('${NODENAME}: removed locks')"
    fi
}

#----------------------------------------------------------------------------
function removeUneededPackages()
{
    # remove old linux versions
    echo
    echo "dpkg --get-selections | grep -E '^linux-(\\w+-){1,2}[4-9]\\.'"
    # shellcheck disable=SC1117
    local -r packages=$(dpkg --get-selections | grep -E '^linux-(\\w+-){1,2}[4-9]\.' | grep -v "$(uname -r | sed -e 's|-generic||')" | awk '{ print  $1 }' | tr '\n' ' ')
    local text=''

    local -i status=0
    if [ "$packages" ]; then
        echo
        echo 'removing OS versions no longer need'
        echo
        echo "sudo /usr/bin/apt-get remove -y $packages; sudo /usr/bin/apt-get purge -y $packages"
        # shellcheck disable=SC2086
        text="$(sudo /usr/bin/apt-get remove -y $packages; sudo /usr/bin/apt-get purge -y $packages)" ||:
        echo "$text"
        status=1
    fi

    if [ "$status" -ne 0 ] || (grep 'sudo apt autoremove' <<< "${text:-}"); then
        echo
        echo 'removing packages that OS says we no longer need'
        text="$(sudo /usr/bin/apt-get autoremove -y)" ||:
        echo "$text"
        text="$(sudo /usr/bin/apt autoremove -y)" ||:
        echo "$text"
    fi
    return 0
}

#----------------------------------------------------------------------------
function report()
{
    echo
    echo
    echo 'Report if we need to reboot and/or run fsck'
    local -a checks=('/var/lib/update-notifier/fsck-at-reboot' '/var/run/reboot-required')
    for fl in "${checks[@]}" ; do
        echo "checking $fl"
        [ -s "$fl" ] || continue
        :> "$JOB_STATUS"
        cat "$fl"
        fl="$(basename "$fl")"
        updateStatus "addWarningBadge('''${NODENAME}: ${fl//-/ }''')"
    done
}

#----------------------------------------------------------------------------
function showLinuxVersions()
{
    echo
    echo
    echo 'Report our linux installations'
    dpkg --get-selections | grep -E '^linux-(\w+-){1,2}[4-9]\.' | grep "$(uname -r | sed -e 's|-generic||')"
}

#----------------------------------------------------------------------------
function showWhatNeedsDone()
{
    # i686 systems are currently on latest release. No more upgrades!
    [ "$(uname -m)" != 'x86_64' ] && return


    local text
    echo
    echo 'Show what needs done'
    echo "/usr/lib/update-notifier/apt-check --human-readable"
    /usr/lib/update-notifier/apt-check --human-readable ||:

    text=$(/usr/lib/ubuntu-release-upgrader/check-new-release --check-dist-upgrade-only) || :
    echo "$text"
    # shellcheck disable=SC2155
    local txt="$(grep 'New release' <<< "$text" ||:)"
    [ -z "$txt" ] || updateStatus "addBadge('yellow.gif','''${NODENAME}: ${txt}''')"
}

#----------------------------------------------------------------------------
function updateStatus()
{
    local -r text=${1:?}

    [ -z "${text:-}" ] && return 0
    [ -s "$JOB_STATUS" ] || (echo "manager.$text"; echo "currentBuild.result = 'UNSTABLE'") > "$JOB_STATUS"
    return 0
}

##########################################################################################################

set -o errtrace
declare -r NODENAME=${1:-$(hostname -s)}
shift

export TERM=linux
export RESULTS="${WORKSPACE:-.}/${NODENAME}.txt"
export ERRORS="${WORKSPACE:-.}/${NODENAME}.errors.txt"
export JOB_STATUS="${WORKSPACE:-.}/status.groovy"

trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT

main "$@" 2>&1 | tee "$RESULTS"
