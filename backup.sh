#!/bin/bash

#---------------------------------------------------------------------------- 
function expandFile() {

   local -r dir="${1:?}"
   local -r file="${2:?}"

    mkdir -p "${dir}"
    cd "${dir}" ||:
    tar xzf "$file"
#    ls "${dir}" >&2
    {
        local f
        while read -r f; do
            sha256sum "$f" | cut -d ' ' -f 1
            echo "$f" >> "${dir}/../files.txt"
        done < <(find . -type f)
     } | sha256sum | cut -d ' ' -f 1
}
#---------------------------------------------------------------------------- 
function main() {

    local -r target="${1:?}"
    :> "$JOB_STATUS"

    local -r filename="$(basename "$target")"
    local -r backupFile="${BACKUP_DIR}/$filename"
    echo "Comparing ${target} with backup: ${backupFile}"

    if [ -e "$backupFile" ]; then
        mkdir -p "${WORKSPACE}/tmp"
        :> "${WORKSPACE}/tmp/files.txt"
        backupSha="$(expandFile "${WORKSPACE}/tmp/backup" "$backupFile")"
        targetSha="$(expandFile "${WORKSPACE}/tmp/target" "$target")"

        [ "$backupSha" = "$targetSha" ] && return 0

        local -a files=()
        mapfile -t files < <(sort -u "${WORKSPACE}/tmp/files.txt")
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
        echo "${diffs} detected between backup: ${backupFile} and ${target}"
    else
        echo '    Backup file does ot exist'
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
    [ "${WORKSPACE}" ] && [ -e "${WORKSPACE}/tmp" ] && rm -rf "${WORKSPACE}/tmp"
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

WORKSPACE="${WORKSPACE:-$(pwd)}"
declare -ri MAX_FILES=${MAX_FILES:-10}
declare -r BACKUP_DIR="${BACKUP_DIR:-/home/bobb/src}"
declare -r NODENAME=$(hostname -f)
export RESULTS="${WORKSPACE:-.}/${NODENAME}.txt" 
export JOB_STATUS="${WORKSPACE:-.}/status.groovy"
export TERM=linux

source /home/bobb/.bin/trap.bashlib
trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT

main "$@" 2>&1 | tee "$RESULTS"
