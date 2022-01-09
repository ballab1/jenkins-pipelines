#!/bin/bash
source /home/bobb/.bin/trap.bashlib


#----------------------------------------------------------------------------
function checkFiles()
{
    local -r tarFile="${1:?}"

    local -a srcFiles=()
    while read -r file; do
        [ -e "$file" ] || continue
        [ -e "${file}/.git" ] || continue
        srcFiles+=( $(sudo find "$file" -type f | grep -v '.git') )
    done < "${PROGRAM_DIR}/tarfiles.lst"

    local -i status=0
    if [ -f "${BACKUP_DIR}/$tarFile" ]; then
        mkdir -p "${TEMP_DIR}/backup" ||:
        pushd "${TEMP_DIR}/backup" > /dev/null ||:

        tar -xvzf "${BACKUP_DIR}/$tarFile" > /dev/null ||:

        local -a dstFiles
        mapfile -t dstFiles < <(find . -type f | sort)
    
        if [ "${#srcFiles[*]}" -ne "${#dstFiles[*]}" ];then
            status=1
        else
            for file in "${srcFiles[@]}";do
                if [ -e ".$file" ] && [ -e "$file" ]; then
                     [ "$(sha256sum ".$file" | cut -d ' ' -f 1)" = "$(sudo sha256sum "$file" | cut -d ' ' -f 1)" ] && continue
                fi
                status=1
                echo "    $file"
             done
        fi
        popd > /dev/null  ||:
    else
        status=1
    fi

    [ "$status" -eq 0 ] && return 0

    echo
    echo "${NODENAME}: Creating backup of files"
    sudo tar -cvzf "${WORKSPACE_DIR}/${tarFile}" "${srcFiles[@]}" &> "${WORKSPACE_DIR}/${tarFile//.tgz}.log" ||:

    [ "$(sha256sum "${WORKSPACE_DIR}/${tarFile}" | cut -d ' ' -f 1)" = "$(sha256sum "${BACKUP_DIR}/$tarFile" | cut -d ' ' -f 1)" ] && return 0

    return 1
}

#---------------------------------------------------------------------------- 
function lastBackup() {

    local -r tarFile="${1:?}"
    local realFile="$(readlink -f "${BACKUP_DIR}/$tarFile")"
    if [ -e "$realFile" ]; then
        echo "$(basename "$realFile" | cut -d '.' -f 3)"
    else
        echo 'no prior backup found'
    fi
}

#---------------------------------------------------------------------------- 
function main() {

    local -r nodeName="${1:?}"
    [ "$nodeName" = 'rasberry' ] && return

    local -r tarfile="${nodeName}.cfg.tgz"
    local last="$(lastBackup "$tarfile")"
    {
        local -i status=0
        local results="$(checkFiles "$tarfile")" && status=$? || status=$?
        if [ "$status" -eq 0 ]; then
            echo "${NODENAME}: no changes detected since '$last'"
            echo "$results"
        else
            echo "${NODENAME}: changes detected since '$last'"
            echo "$results"
            saveBackup "$tarfile"
        fi
        echo
 } | tee "${WORKSPACE_DIR}/${nodeName}.log"
    return 0
}

#----------------------------------------------------------------------------
function onexit()
{
    echo
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    return 0
}

#---------------------------------------------------------------------------- 
function saveBackup() {

    local -r filename="${1:?}"
    local -r base="${filename%.*}" 

    :> "$JOB_STATUS"
    sudo mkdir -p "${BACKUP_DIR}/$base"

    local newFile="${BACKUP_DIR}/${base}/${base}.$(date +"%Y%m%d").${filename##*.}"
    sudo cp "$filename" "$newFile"
    echo "${NODENAME}: saved $newFile"
    updateStatus "addBadge('completed.gif','${NODENAME}: backed up to $newFile')"

    [ -e "${BACKUP_DIR}/$filename" ] && sudo rm "${BACKUP_DIR}/$filename"
    sudo ln -s "$newFile" "${BACKUP_DIR}/$filename"

    local -a files
    mapfile -t files < <(find "${BACKUP_DIR}/$base" -maxdepth 1 -mindepth 1 -type f | sort -r)

    local -i i="${#files[*]}"
    while [ $(( i-- )) -ge "$MAX_FILES" ]; do
        echo "${NODENAME}: deleting ${files[$i]}"
        sudo rm "${files[$i]}"
        updateStatus "addBadge('completed.gif','${NODENAME}: backed up to $newFile\\nremoved ${files[$i]}')" 'force'
    done
    return 0
}

#----------------------------------------------------------------------------
function updateStatus()
{
    local -r text=${1:?}
    local -r force=${2:-}

    [ -z "${text:-}" ] && return 0
    if [ "${force:-}" ] || [ ! -s "$JOB_STATUS" ]; then
        (echo "manager.$text"; echo "currentBuild.result = 'UNSTABLE'") > "$JOB_STATUS"
    fi
    return 0
}
 
##########################################################################################################

set -o errtrace

declare -ri MAX_FILES=${MAX_FILES:-10}
declare -r BACKUP_DIR="${BACKUP_DIR:-/home/bobb/src}"
declare -r PROGRAM_DIR="$(dirname "${BASH_SOURCE[0]}")"
declare -r WORKSPACE_DIR="${WORKSPACE:-pwd}"
declare -r TEMP_DIR='/tmp/backups'

export TERM=linux
declare -r NODENAME=$(hostname -f)
export RESULTS="${WORKSPACE_DIR}/${NODENAME}.txt" 
export JOB_STATUS=${WORKSPACE_DIR}/status.groovy 

trap onexit ERR
trap onexit INT
trap onexit PIPE
trap onexit EXIT

declare -i status=0
{
   main "$@" && status=$? || status=$?
} 2>&1 | tee "$RESULTS"

exit 0
