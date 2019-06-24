#!/bin/bash

# scan registry and delete folders with no sub-folders in

function removeEmptyTags()
{
    local dir=${1:?}
    while read -r dir; do
        # ignore folder if it is a special registry folder
        [ $dir = _layers ] && continue
        [ $dir = _manifest ] && continue
        [ $dir = _uploads ] && continue

        local -a other

        # recurse into subfolders if there are any
        mapfile -t other < <( ls -1A "$dir" | grep -vE '_manifests|_uploads|_layers' )
        [ "${#other[*]}" -eq 0 ] || removeEmptyTags "$dir"

        # verify that there are only registry folders (skip if these do not exist)
        mapfile -t other < <( ls -1A "$dir" | grep -E '_manifests|_uploads|_layers' )
        [ "${#other[*]}" -gt 0 ] || continue

        # verify that there are only registry folders
        if [ -d "${dir}/_manifests" ]; then
            [ -d "${dir}/_manifests/revisions" ] && [ -d "${dir}/_manifests/tags" ] || continue
            [ $(ls -1A "${dir}/_manifests/tags" | wc -l) -eq 0 ] || continue
            rm -rf "${dir}/_manifests"
        fi

        # remove this folder
        rm -rf "${dir}/_layers"
        rm -rf "${dir}/_uploads"
        [ $(ls -1A "${dir}/" | wc -l) -eq 0 ] || continue

        echo "$dir : deleted"
        removedRepos+=( ${dir:2} )
        rmdir "${dir}"

    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort)
}

#############################################################################################
function kafkaJson()
{
    echo -n '{ "blocksAtStart": '$blocksAtStart', '
    echo -n '"blocksAfterGC": '$blocksAfterGC', '
    echo -n '"blocksAfterRemovingEmptyTags": '$blocksAfterRemovingEmptyTags', '
    echo -n '"blocksRecovered": '$blocksRecovered', '
    echo '"deletedRepos": '${#removedRepos[*]}' }'
}

#############################################################################################
function show_summary()
{
    echo
    echo
    df

    echo
    echo
    echo "available blocks at start:                   $blocksAtStart"
    echo "available blocks after GC:                   $blocksAfterGC"
    echo "available blocks after removing empty tags:  $blocksAfterRemovingEmptyTags"
    echo "blocks recovered:                            $(( blocksAfterRemovingEmptyTags - blocksAtStart ))"
    echo "repository directories deleted:              ${#removedRepos[*]}"
    if [ "${#removedRepos[*]}" -gt 0 ]; then
        echo 'Removed repositories:'
        printf '    %s\n' "${removedRepos[@]}"
    fi
    echo
}
#############################################################################################

# Use the Unofficial Bash Strict Mode
set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

set +o verbose
set +o xtrace
export TERM=linux


# ensure this script is run as root
if [[ $EUID != 0 ]]; then
  sudo $0
  exit
fi

declare -i blocksAtStart blocksAfterGC blocksAfterRemovingEmptyTags
declare -a removedRepos=()

blocksAtStart=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

echo
echo
echo
/usr/bin/docker-registry garbage-collect /etc/docker/registry/config.yml
blocksAfterGC=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

echo
echo
pushd '/var/lib/docker-registry/docker/registry/v2/repositories'
removeEmptyTags '.'
popd
blocksAfterRemovingEmptyTags=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

show_summary | tee summary.log
chmod 666 summary.log
