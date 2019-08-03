#!/bin/bash

#----------------------------------------------------------------------------------------------
function process()
{
    local -r recurse=${1:-'false'}
    local -r report=${2:-'false'}


    echo
    echo "$(hostname):"
    local moduleDir
    while read -r moduleDir; do
        processDir "$moduleDir" "${report:-}" "${recurse:-}"
    done < <(cat "$dirsFile")
}

#----------------------------------------------------------------------------------------------
function processDir()
{
    local -r dir=${1:?}
    local -r report=${2:-'false'}
    local -r recurse=${3:-'false'}

    [ -e "${dir}/.git" ] || return 0

    local -r myDir="$(pwd)"
    cd "$dir"
    [ "$report" = 'false' ] && updateGitDir "$moduleDir" "${recurse:-}"
    if [ "$recurse" != 'false' ]; then
        local moduleDir
        while read -r moduleDir; do
            processDir "$moduleDir" "${report:-}" "${recurse:-}"
        done < <(git submodule status --recursive | awk '{print $2}')
    fi
    echo "    $(git rev-parse HEAD) : $(pwd)"
    cd "$myDir"
    return 0
}

#----------------------------------------------------------------------------------------------
function updateGitDir()
{
set -x
    local -r branches="$(git branch)"
    local -r ref="$(echo "$branches" | awk '{if (NF>1) {sub("([^A-Za-z0-9_/])","",$2); print $2}}' )"

    if [ "${ref:-}" ]; then
        git fetch --all --recurse-submodules
        local branch
        for branch in $(echo "$branches" | awk '{print substr($0,3)}'); do
            git checkout "$branch"
            git reset --hard "origin/$branch"
        done
        [ "$ref" != 'HEAD' ] && git checkout "$ref"
    fi
set +x
    return 0
}

#----------------------------------------------------------------------------------------------

declare dirsFile="$(hostname).dirs"
if [ -e "$dirsFile" ]; then

    process 'false' 'false'
    process 'false' 'true'
    process 'false' 'true' > "$(hostname).inf"

fi
exit 0
