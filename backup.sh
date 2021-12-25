#!/bin/bash -x
source /home/bobb/.bin/trap.bashlib

#---------------------------------------------------------------------------- 
function main() {

    local -r target="${1:?}"
    :> "$JOB_STATUS"

    local -r filename="$(basename "$target")"
    local -r backupFile="${BACKUP_DIR}/$filename"
    if [ -e "$backupFile" ]; then
        [ "$(sha256sum "$target" | cut -d ' ' -f 1)" = "$(sha256sum "$backupFile" | cut -d ' ' -f 1)" ] && return 0
    fi

    local -r base="${filename%.*}" 
    mkdir -p "${BACKUP_DIR}/$base"

    local newfile="${BACKUP_DIR}/${base}/${base}.$(date +"%Y%m%d").${filename##*.}"
    cp "$target" "$newfile"
    updateStatus "addBadge('completed.gif','${NODENAME}: backed up to ${newfile}')"

    [ -e "$backupFile" ] && rm "$backupFile"
    ln -s "$newfile" "$backupFile"

    local -a files
    mapfile -t files < <(find "${BACKUP_DIR}/$base" -maxdepth 1 -mindepth 1 -type f | sort -r)

    local -i i="${#files[*]}"
    while [ $(( i-- )) -ge "$MAX_FILES" ]; do
        rm "${files[$i]}"
        updateStatus "addBadge('completed.gif','${NODENAME}: backed up to ${newfile}\\nremoved ${files[$i]}')" 'force'
    done
    return 0
}

#----------------------------------------------------------------------------
function onexit()
{
    echo
    return 1
}

#----------------------------------------------------------------------------
function updateStatus()
{
    local -r text=${1:?}
    local -r force=${2:-}

    [ -z "${text:-}" ] && return 0
    if [ "${force:-}" ] || [ ! -s "$JOB_STATUS" ]; then
        (set -x;echo "manager.$text"; echo "currentBuild.result = 'UNSTABLE'") > "$JOB_STATUS"
    fi
    return 0
}
 
##########################################################################################################

set -o errtrace

declare -ri MAX_FILES=${MAX_FILES:-10}
declare -r BACKUP_DIR="${BACKUP_DIR:-/home/bobb/src}"

export TERM=linux
declare -r NODENAME=$(hostname -f)
export RESULTS="${WORKSPACE:-.}/${NODENAME}.txt" 
export JOB_STATUS="${WORKSPACE:-.}/status.groovy"

trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT

main "$@" 2>&1 | tee "$RESULTS"
