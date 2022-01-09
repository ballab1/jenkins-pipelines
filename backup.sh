#!/bin/bash
source /home/bobb/.bin/trap.bashlib

#---------------------------------------------------------------------------- 
function main() {

    local -r target="${1:?}"
    :> "$JOB_STATUS"

    local -r filename="$(basename "$target")"
    local -r backupFile="${BACKUP_DIR}/$filename"
    if [ -e "$backupFile" ]; then
        [ "$(tar xOzf "$target" | sha256sum | cut -d ' ' -f 1)" = "$( tar xOzf "$backupFile" | sha256sum | cut -d ' ' -f 1)" ] && return 0
        mkdir -p "${WORKSPACE}/tmp/backup"
        mkdir -p "${WORKSPACE}/tmp/target"
        local -a files=()
        mapfile -t files <((cd "${WORKSPACE}/tmp/backup" && tar xzf "$backupFile"; cd "${WORKSPACE}/tmp/target" && tar xzf "$target") | sort -u)
        local file diffs=0
        for file in "${files[@]}"; do
            if [ ! -f "backup/$file"  ]; then
                echo "removed file: '$file'"
                ((diffs++)) ||:
            elif [ ! -f "target/$file"  ]; then
                echo "new file:     '$file'"
                ((diffs++)) ||:
            elif diff -q "backup/$file" "target/$file"; then
                echo "files differ:  'backup/$file' & 'target/$file'"
                ((diffs++)) ||:
            else
                rm "target/$file" "backup/$file"
            fi
        done
        [ "$diffs" -eq 0 ] && return 0
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
    [ "${WORKSPACE}" ] && [ -f "${WORKSPACE}/tmp" ] && rm -rf "${WORKSPACE}/tmp"
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
