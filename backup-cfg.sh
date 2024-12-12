#!/bin/bash

#----------------------------------------------------------------------------
function expandFile() {

    local -r dir="${1:?}"
    local -r file="${2:?}"
    local -r filelist="${3:?}"

    [ -f "$filelist" ] || return
    mkdir -p "$dir"
    cd "$dir" ||:
    {
        local f
        while read -r f; do
            [ -f "$f" ] || continue
            sha256sum "$f" | cut -d ' ' -f 1
            echo "$f" >> "$filelist"
        done < <(tar xvzf "$file")
     } | sha256sum | cut -d ' ' -f 1
}

#----------------------------------------------------------------------------
function build_tar() {

    local -r tarFile="${1:?}"

    local -a srcFiles=()
    while read -r file; do
        [ -e "$file" ] || continue
        [ -e "${file}/.git" ] && continue
        #shellcheck disable=SC2207
        srcFiles+=( $(sudo find "$file" -type f | grep -v '.git' ||:) )
    done < "${WORKSPACE}/tarfiles.lst"

    echo
    echo "${NODENAME}: Creating backup of files"
    (sudo tar -cvzf "$tarFile" "${srcFiles[@]}") 2>&1 | tee "${tarFile//.tgz}.log"
}

#----------------------------------------------------------------------------
function main() {

#    [ -d "$LATEST_CONTENT" ] || return 0
    [ ! -d "$WORKSPACE" ] && mkdir -p "$WORKSPACE"

#    cd "$LATEST_CONTENT" ||:
    local -r latest_tar="${WORKSPACE}/${TARGET}.cfg.tgz"
    build_tar "$latest_tar"

    :> "$JOB_STATUS"

    # use the sha256 values to compare contents of latest dir and last tarfile
    local -r previousFile="${BACKUP_DIR}/$(basename "$latest_tar")"
    if [ ! -e "$previousFile" ]; then
        echo '    Backup file does not exist'
    else
        echo "Comparing '${LATEST_CONTENT}' with contents of previous: '${previousFile}'"

        local -r work_dir="${WORKSPACE}/tmp/${TARGET}"
        mkdir -p "$work_dir"

        # check the sha of every file from previous and latest combined into a single sha, and build filelist of all files
        local -r filelist="${work_dir}/files.txt"
        :> "$filelist"
        previousSha="$(expandFile "${work_dir}/previous" "$previousFile" "$filelist")"
        targetSha="$(expandFile "${work_dir}/latest" "$latest_tar" "$filelist")"
        if [ "${#previousSha}" -gt 0 ] && [ "${#targetSha}" -gt 0 ]; then
            [ "$previousSha" = "$targetSha" ] && return 0
        fi

        # must be a difference, loop through every file to find what changed
        local -a files=()
        mapfile -t files < <(sort -u "$filelist")
        local file diffs=0
        for file in "${files[@]}"; do
            if [ ! -f "${work_dir}/previous/$file" ] && [ ! -f "${work_dir}/latest/$file" ]; then
                continue
            elif [ ! -f "${work_dir}/latest/$file"  ]; then
                echo "   removed file:  '$file'"
                ((diffs++)) ||:
            elif [ ! -f "${work_dir}/previous/$file"  ]; then
                echo "   new file:      '$file'"
                ((diffs++)) ||:
            elif ! (diff -q "${work_dir}/previous/$file" "${work_dir}/latest/$file" &> /dev/null); then
                echo "   files differ:  'previous/$file' & 'latest/$file'"
                ((diffs++)) ||:
            else
                rm "${work_dir}/previous/$file" "${work_dir}/latest/$file"
            fi
        done
        [ "$diffs" -eq 0 ] && return 0
        echo "${diffs} differences detected between previous: ${previousFile} and ${latest_tar}"
    fi

    # copy the latest tarfile to the backup location and create a symlink
    mkdir -p "${BACKUP_DIR}/$TARGET"
    local newfile="${BACKUP_DIR}/${TARGET}/${TARGET}.$(date +"%Y%m%d").${latest_tar##*.}"
    cp "$latest_tar" "$newfile"
    updateStatus 'completed.gif' "${LATEST_CONTENT}: backed up to ${newfile}"
    [ -e "$previousFile" ] && rm "$previousFile"
    ln -s "$newfile" "$previousFile"


    # remove old files to keep a fixed number of backups
    local -a files
    mapfile -t files < <(find "${BACKUP_DIR}/$TARGET" -maxdepth 1 -mindepth 1 -type f | sort -r)
    local -i i="${#files[*]}"
    while [[ $(( i-- )) -ge "$MAX_FILES" ]]; do
        rm "${files[$i]}"
        updateStatus 'completed.gif' "removed ${files[$i]}" 'force'
    done
    return 0
}

#----------------------------------------------------------------------------
function onexit()
{
    [ -e "${WORKSPACE}/tmp/${TARGET}" ] && rm -rf "${WORKSPACE}/tmp/${TARGET}"
    if [ -s "$JOB_STATUS" ]; then
      echo "= $JOB_STATUS contains =================================="
      cat "$JOB_STATUS"
      echo '========================================================='
    fi
    echo
    return 0
}

#----------------------------------------------------------------------------
function updateStatus()
{
    local -r badge=${1:?}
    local -r text=${2:?}
    local -r force=${3:-}

    if [ ! -s "$JOB_STATUS" ] || [ "${force:-}" ]; then
        echo 'Updating status.groovy' >&2
        {
            echo "$badge"
            echo "$text"
            echo 'UNSTABLE'
         } > "$JOB_STATUS"
    fi
    return 0
}

##########################################################################################################

set -o errtrace

declare -r LATEST_CONTENT="${1:?}"
declare -ri MAX_FILES=${MAX_FILES:-10}
declare -r BACKUP_DIR="${BACKUP_DIR:-/home/bobb/src}"
declare -r NODENAME="$(hostname -f)"
declare -r TARGET="$NODENAME"
export WORKSPACE="${WORKSPACE:-$(pwd)}"
export RESULTS="${WORKSPACE}/${NODENAME}.txt"
export JOB_STATUS=${WORKSPACE}/status.groovy

export TERM=linux

#shellcheck disable=SC1091
source /home/bobb/.bin/trap.bashlib
trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT


main 2>&1 | tee "$RESULTS"
