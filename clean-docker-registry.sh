#!/bin/bash

# scan registry and delete folders with no sub-folders in

function removeEmptyTags()
{
    local dir=${1:?}

    while read -r dir; do
        [ $dir = _layers ] && continue
        [ $dir = _manifest ] && continue
        [ $dir = _uploads ] && continue

        local -a other
        mapfile -t other < <( ls -1A "$dir" | grep -vE '_manifests|_uploads|_layers' )
        [ "${#other[*]}" -eq 0 ] || removeEmptyTags "$dir"

        mapfile -t other < <( ls -1A "$dir" | grep -E '_manifests|_uploads|_layers' )
        [ "${#other[*]}" -gt 0 ] || continue

        [ -d "${dir}/_manifests/revisions" ] && [ -d "${dir}/_manifests/tags" ] || continue
        [ $(ls -1A "${dir}/_manifests/tags" | wc -l) -eq 0 ] || continue

        rm -rf "${dir}/_manifests"
        rm -rf "${dir}/_layers"
        rm -rf "${dir}/_uploads"
        echo "$dir : deleted"

        [ $(ls -1A "${dir}/" | wc -l) -eq 0 ] || continue
        rmdir "${dir}"

    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort)
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

declare -i blocksAtStart=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

echo
echo
echo
/usr/bin/docker-registry garbage-collect /etc/docker/registry/config.yml
declare -i blocksAfterGC=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

echo
echo
removeEmptyTags '/var/lib/docker-registry/docker/registry/v2/repositories'
declare -i blocksAfterRemovingEmptyTags=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')


echo
echo
df

echo
echo
echo "blocks at start:                   $blocksAtStart"
echo "blocks after GC:                   $blocksAfterGC"
echo "blocks after removing empty tags:  $blocksAfterRemovingEmptyTags"
echo "blocks recovered:  $(( blocksAfterRemovingEmptyTags - $blocksAtStart ))"
echo
