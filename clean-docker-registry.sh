#!/bin/bash

# scan registry and delete folders with no sub-folders in

# setting up docker-registry:
#   apt-get -y docker-registry

# then setup where images get stored.
# either change docker.registry.config.yml:
#    sed -iE -e 's|\srootdirectory:\s.+$| rootdirectory: /var/lib/docker-registry|' /etc/docker/registry/config.yml
#or change mount point by adding:
#root@ubuntu-s2:~# mkdir /media/ext3-d/docker-registry
#root@ubuntu-s2:~# chown docker-registry:docker-registry /media/ext3-d/docker-registry
#fstab:
#    /media/ext3-d/docker-registry /var/lib/docker-registry   none    bind

#----------------------------------------------------------------------------
function currate_images() {

    # define registries and #images we keep for each
    local -A registries=(
      ['docker.io']=6
      ['i386-ubuntu']=2
      ['docker.redpanda.com']=4
      ['gcr.io']=4
      ['quay.io']=4
      ['registry.k8s.io']=4
    )

    (cd bin; git-crypt unlock /home/bobb/src/keys/work-stuff.key)
    unset USER
    unset USERNAME
    ./updateBin.sh
    export __SECRETS_FILE=/home/bobb/.inf/secret.properties
    for registry in "${!registries[@]}"; do
        echo
	echo "currating images in ${registry}"
    	./bin/docker-utilities delete \
            --max "${registries[$registry]}" \
            --no_confirm_delete \
            "${registry}"'/.*' ||:
    done
}

#----------------------------------------------------------------------------
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
            sudo rm -rf "${dir}/_manifests"
        fi

        # remove this folder
        sudo rm -rf "${dir}/_layers"
        sudo rm -rf "${dir}/_uploads"
        [ $(ls -1A "${dir}/" | wc -l) -eq 0 ] || continue

        echo "$dir : deleted"
        removedRepos+=( ${dir:2} )
        sudo rmdir "${dir}"

    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort)
}

#----------------------------------------------------------------------------
function kafkaJson()
{
    echo -n '{ "blocksAtStart": '$blocksAtStart', '
    echo -n '"blocksAfterGC": '$blocksAfterGC', '
    echo -n '"blocksAfterRemovingEmptyTags": '$blocksAfterRemovingEmptyTags', '
    echo -n '"blocksRecovered": '$blocksRecovered', '
    echo '"deletedRepos": '${#removedRepos[*]}' }'
    echo
}

#----------------------------------------------------------------------------
function run_garbage_collection() {

    local -i blocksAtStart blocksAfterGC blocksAfterRemovingEmptyTags
    local -a removedRepos=()

    blocksAtStart=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

    echo
    echo
    echo
    sudo /usr/bin/docker-registry garbage-collect /etc/docker/registry/config.yml > "$COLLECTION_LOG"
    blocksAfterGC=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

    echo
    echo
    pushd '/var/lib/docker-registry/docker/registry/v2/repositories'
    removeEmptyTags '.'
    popd
    blocksAfterRemovingEmptyTags=$(df /dev/sdb1 | sed '1d' | awk '{print $4}')

    show_summary | tee "$LOG"
    chmod 666 "$LOG"
}

#----------------------------------------------------------------------------
function show_summary()
{
    echo
    grep 'blobs marked' "$COLLECTION_LOG"
    echo
    echo
    echo 'Filesystem                         1K-blocks       Used  Available Use% Mounted on'
    df | grep -E '(^/dev|Registry)'

    local -i blocksRecovered=$(( blocksAfterRemovingEmptyTags - blocksAtStart ))
    echo
    echo
    echo "available blocks at start:                   $blocksAtStart"
    echo "available blocks after GC:                   $blocksAfterGC"
    echo "available blocks after removing empty tags:  $blocksAfterRemovingEmptyTags"
    echo "blocks recovered:                            $blocksRecovered"
    echo "repository directories deleted:              ${#removedRepos[*]}"
    if [ "${#removedRepos[*]}" -gt 0 ]; then
        echo 'Removed repositories:'
        printf '    %s\n' "${removedRepos[@]}"
    fi
    echo
    [ "$blocksRecovered" -eq 0 ] || updateStatus 'warning.gif' "${blocksRecovered} blocks recovered"
}

#----------------------------------------------------------------------------
function updateStatus()
{
    local -r badge=${1:?}
    local -r text=${2:?}
    local -r force=${3:-}

    if [ ! -s "$JOB_STATUS" ] || [ "${force:-}" ]; then
        echo "Updating $JOB_STATUS" >&2
        {
            echo "$badge"
            echo "$text"
            echo 'UNSTABLE'
         } > "$JOB_STATUS"
    fi
    return 0
}

#############################################################################################

# Use the Unofficial Bash Strict Mode
set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

set +o verbose
#set +o xtrace
export TERM=linux
declare -r arg="${1:?}"
declare -r JOB_STATUS="${2:?}"
declare -r LOG="${3:?}"
declare -r COLLECTION_LOG='garbage_collection.log'
:> "$LOG"

case "$arg" in
   currate_images)
     "$arg";;
   run_garbage_collection)
     "$arg";;
   *)
     echo 'invalid option specified'
     exit 1;;
esac
