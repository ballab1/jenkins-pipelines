#!/bin/bash

#----------------------------------------------------------------------------------------------
function process()
{
    local -r recurse=${1:-'false'}
    local -r report=${2:-'false'}
    local -i status stat

    echo
    echo "$(hostname):"
    local moduleDir
    while read -r moduleDir; do
        processDir "$moduleDir" "${report:-}" "${recurse:-}" && stat=$? || stat=$?
        [ $stat -eq 0 ] || status=$stat
    done < <(cat "$dirsFile")
    return $status
}

#----------------------------------------------------------------------------------------------
function processDir()
{
    local -r dir=${1:?}
    local -r report=${2:-'false'}
    local -r recurse=${3:-'false'}
    local -i status stat

    [ -e "${dir}/.git" ] || return 0

    local -r myDir="$(pwd)"
    cd "$dir"
    if [ "$report" = 'false' ]; then
        updateGitDir "$moduleDir" "${recurse:-}" && status=$? || status=$?
    fi
    if [ "$recurse" != 'false' ]; then
        local moduleDir
        while read -r moduleDir; do
            processDir "$moduleDir" "${report:-}" "${recurse:-}" && stat=$? || stat=$?
            [ $stat -eq 0 ] || status=$stat
        done < <(git submodule status --recursive | awk '{print $2}')
    fi
    echo "    $(git rev-parse HEAD) : $(pwd)"
    cd "$myDir"
    return $status
}

#----------------------------------------------------------------------------------------------
function run()
{
    [ "${DEBUG:-0}" -ne 0 ] && (echo -e "${grey}$(printf '%s ' "$@")$reset" >&2)
    eval $@ > /dev/null
}

#----------------------------------------------------------------------------------------------
function updateGitDir()
{
    # do nothing if directory is dirty. just report error
    [ $(git status --porcelain) ] && return 1

    local -r branches="$(DEBUG_TRACE=1 git branch)"
    local -r ref="$(echo "$branches" | awk '{if (NF>1) {sub("([^A-Za-z0-9_/])","",$2); print $2}}' )"

    if [ "${ref:-}" ]; then
        run git fetch --all --recurse-submodules
        local branch
        for branch in $(echo "$branches" | awk '{print substr($0,3)}'); do
            if [[ "$branch" = \(HEAD* ]]; then
                run git reset --hard "origin/master"
            else
                run git checkout "$branch"
                run git reset --hard "origin/$branch"
            fi
        done
    fi
    return 0
}

#----------------------------------------------------------------------------------------------

declare -r grey='\e[90m'
declare -r white='\e[97m'
declare -r reset='\e[0m'
declare -r dirsFile="$(hostname).dirs"
declare -i status=0

if [ -e "$dirsFile" ]; then

    process 'false' 'false' && status=$? || status=$?
    ( process 'false' 'true' ||: ) | tee "$(hostname).inf"

fi
exit 0
