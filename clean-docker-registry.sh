#!/bin/bash

# scan registry and delete folders with no sub-folders in

# Use the Unofficial Bash Strict Mode
set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

set +o verbose
set +o xtrace
export TERM=linux


function removeEmptyTags()
{
    local -r dir=${1:?}

    local -a dirs
    local errors=$(mktemp)
    echo -n " checking $(basename "$dir")"
    mapfile -t dirs < <(ls -1A "${dir}/_manifests/tags" 2> "$errors")
    if [ "$(< "$errors")" ]; then
        echo -n $errors
    elif [ ${#dirs[*]} -eq 0 ]; then
        rm -rf "$dir"
        echo -n ': deleted'
    fi
    echo
}

# ensure this script is run as root
if [[ $EUID != 0 ]]; then
  sudo $0
  exit
fi

echo
echo
declare -i status
for dir in $(find /var/lib/docker-registry/docker/registry/v2/repositories/ -mindepth 1 -maxdepth 1 -type d -name '*' | sort); do
    removeEmptyTags "$dir"
done
echo
df
/usr/bin/docker-registry garbage-collect /etc/docker/registry/config.yml
df

