#!/bin/bash -x

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
    [ "$(git status --porcelain --ignore-submodules)" ] && return 1

    local -r ref="$(git rev-parse --abbrev-ref HEAD)"

    run git fetch --all --recurse-submodules
    local branch
    local -a branches
    mapfile -t branches < <(git branch | sed -E 's|^..||')
    readonly branches
    for branch in "${branches[@]}"; do
        if [[ "${branch:0:5}" = '(HEAD' ]]; then
            run git reset --hard "origin/master"
        else
            run git checkout "$branch"
            run git reset --hard "origin/$branch"
        fi
    done
    if [ "$ref" = HEAD ]; then
        run git reset --hard "origin/master"
    else
        run git checkout "$ref"
    fi
    
    
    # de-git-crypt
    if [ "$(grep -c 'git-crypt')" -gt 0 ]; then
        local repo="$(git remote -v |awk '{split($2, arr, "/"); sub(".git","",arr[3]);print arr[5]; exit}')"
        local keyFile="/home/bobb/src/keys/${repo}.key"
        [ -e "$keyFile" ] && git-grypt unlock "$keyFile"
    fi
    return 0
}

#----------------------------------------------------------------------------------------------

declare -r grey='\e[90m'
declare -r white='\e[97m'
declare -r reset='\e[0m'
declare -i status=0


declare host="${NODE_NAME:-$(hostname)}"
declare -r results="${1:-${host}}.inf"
declare -r dirsFile="${host}.dirs"

if [ -e "$dirsFile" ]; then

    process 'false' 'false' && status=$? || status=$?
    ( process 'false' 'true' ||: ) | tee "$results"

fi
exit 0
