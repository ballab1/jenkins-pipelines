#!/bin/bash

#-----------------------------------------------------------------------------------------------
function scanShareFiles.fileData() {

    local file="$(basename $1)"

    local name="$(basename "$file")"
    local folder="$(cd "$(dirname "$file")"; pwd)"
    name="${name//\"/\\\"}"
    folder="${folder//\"/\\\"}"

    local -A stat_vals
    eval "stat_vals=( $(stat --format="['mount_point']='%m' ['time_of_birth']='%w'" "$1") )"
    local mount_source="$(grep -E '\s'"${stat_vals['mount_point']}"'\s' /etc/fstab | awk '{print $1}')"

    local tob="${stat_vals['time_of_birth']}"
    [ "$tob" = '-' ] && tob='unknown'

    echo -n '{"name":"'"$name"'",' \
            '"folder":"'"$folder"'",' \
            '"mount_point":"'"${stat_vals['mount_point']}"'",' \
            '"mount_source":"'"$mount_source"'",'

    if [ -h "$file" ]; then
        local ref2="$(readlink -f "$file" 2>/dev/null ||:)"
        if [ "${ref2:-}" ]; then
            echo -n '"symlink_reference":"'"$ref2"'",'
        else
            echo -n '"symlink_reference":null,'
            local ref="$(stat --format='%N' "$file" | awk '{print  substr($3,2,length($3)-2) }')"
            echo -n '"link_reference":"'"$ref"'",'
        fi
    fi
    [ -f "$file" ] && echo -n '"sha256":"'"$( sha256sum -b "$file" | cut -d ' ' -f 1 )"'",'

    local -a fields=( '"size":%s,'
                      '"blocks":%b,'
                      '"block_size":%B,'
                      '"xfr_size_hint":%o,'
                      '"device_number":%d,'
                      '"file_type":"%F",'
                      '"uid":%u,'
                      '"uname":"%U",'
                      '"gid":%g,'
                      '"gname":"%G",'
                      '"access_rights":"%a",'
                      '"access_rights__HRF":"%A",'
                      '"inode":%i,'
                      '"hard_links":%h,'
                      '"raw_mode":"0x%f",'
                      '"device_type":"0x%t:0x%T",'
                      '"file_created":%W,'
                      '"file_created__HRF":"'"$tob"'",'
                      '"last_access":%X,'
                      '"last_access__HRF":"%x",'
                      '"last_modified":%Y,'
                      '"last_modified__HRF":"%y",'
                      '"last_status_change":%Z,'
                      '"last_status_change__HRF":"%z"}\n' )

    stat --printf="$(echo ${fields[*]})" "$file"
}

#-----------------------------------------------------------------------------------------------
function scanShareFiles.old_fileData() {

    echo -n '{'
    json.encodeField "name"                                               "$(basename "$(stat --format='%n' "$1")")" 'string'
    echo -n ','
    json.encodeField "folder"                                             "$(cd "$(dirname "$1")"; pwd)" 'string'
    #  decode this to real mountpoint. Also remove this string from 'folder' and add real mount point without host.
    #  unless, mountpoint is local in which case host is fqdn
    echo -n ','
    local mount_point="$(grep -E '\s'"$(stat --format='%m' "$1")"'\s' /etc/fstab | awk '{print $1}')"
    json.encodeField "mount_point"                                        "$mount_point" 'string'
    if [ -h "$1" ]; then
        echo -n ','
        json.encodeField "link_reference"                                 "$(readlink -f "$1" )" 'string'
    fi
    if [ -f "$1" ]; then
        echo -n ','
        json.encodeField "sha256"                                         "$( sha256sum -b "$1" | awk '{ print $1 }' )" 'string'
    fi

    echo -n ','
    json.encodeField "size"                                               "$(stat --format='%s' "$1")" 'integer'
    echo -n ','
    json.encodeField "blocks"                                             "$(stat --format='%b' "$1")" 'integer'
    echo -n ','
    json.encodeField "block_size"                                         "$(stat --format='%B' "$1")" 'integer'
    echo -n ','
    json.encodeField "xfr_size_hint"                                      "$(stat --format='%o' "$1")" 'integer'
    echo -n ','
    json.encodeField "device_number"                                      "$(stat --format='%d' "$1")" 'integer'
    echo -n ','
    json.encodeField "file_type"                                          "$(stat --format='%F' "$1")" 'string'
    echo -n ','
    json.encodeField "uid"                                                "$(stat --format='%u' "$1")" 'string'
    echo -n ','
    json.encodeField "uname"                                              "$(stat --format='%U' "$1")" 'string'
    echo -n ','
    json.encodeField "gid"                                                "$(stat --format='%g' "$1")" 'string'
    echo -n ','
    json.encodeField "gname"                                              "$(stat --format='%G' "$1")" 'string'
    echo -n ','
    json.encodeField "access_rights"                                      "$(stat --format='%a' "$1")" 'string'
    echo -n ','
    json.encodeField "access_rights__HRF"                                 "$(stat --format='%A' "$1")" 'string'
    echo -n ','
    json.encodeField "inode"                                              "$(stat --format='%i' "$1")" 'integer'
    echo -n ','
    json.encodeField "hard_links"                                         "$(stat --format='%h' "$1")" 'integer'
    echo -n ','
    json.encodeField "raw_mode"                                           "$(stat --format='0x%f' "$1")" 'string'
    echo -n ','
    json.encodeField "device_type"                                        "$(stat --format='0x%t:0x%T' "$1")" 'string'

    local tob="$(stat --printf='%w' "$1")"
    [ "$tob" = '-' ] && tob='unknown'
    echo -n ','
    json.encodeField "file_created"                                       "$(stat --format='%W' "$1")" 'integer'
    echo -n ','
    json.encodeField "file_created__HRF"                                  "$tob" 'string'
    echo -n ','
    json.encodeField "last_access"                                        "$(stat --format='%X' "$1")" 'integer'
    echo -n ','
    json.encodeField "last_access__HRF"                                   "$(stat --format='%x' "$1")" 'string'
    echo -n ','
    json.encodeField "last_modified"                                      "$(stat --format='%Y' "$1")" 'integer'
    echo -n ','
    json.encodeField "last_modified__HRF"                                 "$(stat --format='%y' "$1")" 'string'
    echo -n ','
    json.encodeField "last_status_change"                                 "$(stat --format='%Z' "$1")" 'integer'
    echo -n ','
    json.encodeField "last_status_change__HRF"                            "$(stat --format='%z' "$1")" 'string'
    echo '}'
}

#-----------------------------------------------------------------------------------------------
function scanShareFiles.main() {

    [ $# -eq 0 ] && return 0
    local file

    for file in "$@"; do
        scanShareFiles.scan "$file"
    done
}

#-----------------------------------------------------------------------------------------------
function scanShareFiles.scan() {

    local file="$1"
    local -i status=0

    if [ "${file:-}" ]; then
#        if [ "$(stat "$file")" = *'Stale file handle' ]; then
#            sudo umount "$file"
#            sudo mount -a
#        fi

#        if [ "$(stat --format='%F' "$file")" = 'directory' ] && [ "$(stat --format='%a' "$file")" != '770' ] ; then
        if [ "$(stat --format='%F' "$file")" = 'directory' ] ; then

            (( DIR_COUNT++ )) || true
            pushd "$file" &> /dev/null

            local -a files
            mapfile -t files < <(ls -A1)
            if [ "${#files[*]}" -ne 0 ]; then
                local oldPrompt="$prompt"
                prompt="+$prompt"
                printf '%s\t[ %d, %d ]\t%s :\t%d files\n' "$prompt" $DIR_COUNT $FILE_COUNT "$file" "${#files[*]}" >&2
                scanShareFiles.main "${files[@]}" && status=$? || status=$?
                prompt="$oldPrompt"
            fi
            popd > /dev/null

        else
            (( FILE_COUNT++ )) || return 0

            local json="$( scanShareFiles.fileData "$file" )" 2>> "$ERROR_FILE"
            [ "${json:-}" ] || return $status

            if [ "${KAFKA_PRODUCER:-}" ] && [ "$KAFKA_BOOTSTRAP_SERVERS" ]; then
                ("$KAFKA_PRODUCER" --server "$KAFKA_BOOTSTRAP_SERVERS" \
                                   --topic 'fileScanner' \
                                   --value "$json"
                ) && status=$? || status=$?
            else

                stdbuf --output 0  echo "$json" >> "$JSON_FILE"
            fi
        fi

    fi
    return $status
}

#-----------------------------------------------------------------------------------------------

# ensure this script is run as root
#if [[ $EUID != 0 ]]; then
#  sudo -E "$0" "$@"
#  exit
#fi

declare -r JSON_FILE="$(pwd)/files.json"
declare -r ERROR_FILE="$(pwd)/errors.txt"
declare -r PROGRAM_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
#declare -r KAFKA_PRODUCER="${PROGRAM_DIR}/kafkaProducer.py"
declare -r loader="${PROGRAM_DIR}/bin/appenv.bashlib"
declare -i FILE_COUNT=0
declare -i DIR_COUNT=0

if [ ! -e "$loader" ]; then
    echo 'Unable to load libraries'
    exit 1
fi
source "$loader"

appenv.loader 'scanShareFiles.scanFiles'

export TERM=linux
declare -i counter=0
declare prompt=''


[ -e "$ERROR_FILE" ] || touch "$ERROR_FILE"
[ -e "$JSON_FILE" ] || touch "$JSON_FILE"
sudo chown bobb:bobb "$JSON_FILE" "$ERROR_FILE"
chmod 666 "$JSON_FILE" "$ERROR_FILE"
:> "$JSON_FILE"
:> "$ERROR_FILE"


scanShareFiles.main "$@"
