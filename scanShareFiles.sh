#!/bin/bash

declare -ir SLEEP_SECS=3
declare -ir SLEEP_CADENCE=100
declare -r  NICE_VAL='+4'

#-----------------------------------------------------------------------------------------------
function scanShareFiles.checkTime() {

    local -ri secondsSinceMidnight=$(date -d "1970-01-01 UTC $(date +%T)" +%s)

    # sleep between 03:03:30 and 03:06:00
    if [ "$secondsSinceMidnight" -gt 11010 ] && [ "$secondsSinceMidnight" -lt 11160 ]; then
        sleep $(( 11160 - $secondsSinceMidnight ))
    fi
    return 0
}

#-----------------------------------------------------------------------------------------------
function scanShareFiles.fileData() {

    json.encodeField "access_rights"                                      "$(stat --format='%a' "$1")"
    echo ','
    json.encodeField "access_rights_in_human_readable_form"               "$(stat --format='%A' "$1")"
    echo ','
    json.encodeField "device_number_decimal"                              "$(stat --format='%d' "$1")"
    echo ','
    json.encodeField "device_number_hex"                                  "$(stat --format='0x%D' "$1")"
    echo ','
    json.encodeField "file_name"                                          "$(basename "$(stat --format='%n' "$1")")"
    echo ','

    local fn="$( stat --printf='%N' "$1" )"
    fn="$(eval echo ${fn//[\xE2\x80\x98\x99]/})"
    json.encodeField "file_name_with_dereference_if_symbolic_link"        "$fn"
    echo ','
    json.encodeField "file_type"                                          "$(stat --format='%F' "$1")"
    echo ','
    json.encodeField "folder"                                             "$( cd "$( dirname "$1" )" && pwd )"
    echo ','
    json.encodeField "inode"                                              "$(stat --format='%i' "$1")"
    echo ','
    json.encodeField "major_device_type_in_hex"                           "$(stat --format='0x%t' "$1")"
    echo ','
    json.encodeField "minor_device_type_in_hex"                           "$(stat --format='0x%T' "$1")"
    echo ','
    if [ "$(stat --format='%a' "$1")" != '770' ]; then
        json.encodeField "mount_point"                                        "$(stat --format='%m' "$1")"
        echo ','
    fi
    json.encodeField "number_of_blocks_allocated"                         "$(stat --format='%b' "$1")"
    echo ','
    json.encodeField "number_of_hard_links"                               "$(stat --format='%h' "$1")"
    echo ','
    json.encodeField "optimal_IO_transfer_size_hint"                      "$(stat --format='%o' "$1")"
    echo ','
    json.encodeField "owner_group"                                        "$(stat --format='%g' "$1")"
    echo ','
    json.encodeField "owner_group_name"                                   "$(stat --format='%G' "$1")"
    echo ','
    json.encodeField "raw_mode"                                           "$(stat --format='0x%f' "$1")"
    echo ','
    json.encodeField "the_size_of_each_block_reported"                    "$(stat --format='%B' "$1")"
    echo ','

    local tob="$(stat --printf='%w' "$1")"
    [ "$tob" = '-' ] && tob='unknown'
    json.encodeField "time_of_file_birth_human_readable"                  "$tob"
    echo ','
    json.encodeField "time_of_file_birth_seconds_since_Epoch"             "$(stat --format='%W' "$1")"
    echo ','
    json.encodeField "time_of_last_access_human_readable"                 "$(stat --format='%x' "$1")"
    echo ','
    json.encodeField "time_of_last_access_seconds_since_Epoch"            "$(stat --format='%X' "$1")"
    echo ','
    json.encodeField "time_of_last_data_modification_human_readable"      "$(stat --format='%y' "$1")"
    echo ','
    json.encodeField "time_of_last_data_modification_seconds_since_Epoch" "$(stat --format='%Y' "$1")"
    echo ','
    json.encodeField "time_of_last_status_change_human_readable"          "$(stat --format='%z' "$1")"
    echo ','
    json.encodeField "time_of_last_status_change_seconds_since__Epoch"    "$(stat --format='%Z' "$1")"
    echo ','
    json.encodeField "total_size"                                         "$(stat --format='%s' "$1")"
    echo ','
    json.encodeField "user_ID_of_owner"                                   "$(stat --format='%u' "$1")"
    echo ','
    json.encodeField "user_name_of_owner"                                 "$(stat --format='%U' "$1")"

    if [ -f "$1" ]; then
        echo ','
        json.encodeField "sha256"                                         "$( sha256sum -b "$1" | awk '{ print $1 }' )"
    fi
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

        if [ "$(stat --format='%F' "$file")" = 'directory' ] && [ "$(stat --format='%a' "$file")" != '770' ] ; then

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
            (( FILE_COUNT++ )) || true
            scanShareFiles.checkTime
            echo "$( json.encodeHash '--' "$(scanShareFiles.fileData "$file")" )" >> "$JSON_FILE"
            sync

            if [ "${KAFKA_PRODUCER:-}" ] && [ "$KAFKA_BOOTSTRAP_SERVERS" ]; then
                ("$KAFKA_PRODUCER" --server "$KAFKA_BOOTSTRAP_SERVERS" \
                                   --topic 'fileScanner' \
                                   --value "$( json.encodeHash '--' "$(scanShareFiles.fileData "$file")" )"
                ) && status=$? || status=$?
            fi
        fi

    fi
    [ $(( ++counter % SLEEP_CADENCE )) -eq 0 ] && sleep $SLEEP_SECS
    return $status
}

#-----------------------------------------------------------------------------------------------

# ensure this script is run as root
if [[ $EUID != 0 ]]; then
  sudo -E "$0" "$@"
  exit
fi

echo "SLEEP_SECS    : $SLEEP_SECS"
echo "SLEEP_CADENCE : $SLEEP_CADENCE"
echo "NICE_VAL      : $NICE_VAL"

declare -r JSON_FILE="$(pwd)/files.json"
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

#sudo renice -n "$NICE_VAL" -p $(ps ax -o pid,cmd | grep -E 'java\s+-jar\s+remoting.jar\s+.+jarCache' | grep -v 'grep' | cut -d ' ' -f 1)

:> "$JSON_FILE"
chown bobb:bobb "$JSON_FILE"
chmod 666 "$JSON_FILE"
scanShareFiles.main /mnt/WDMyCloud /mnt/Guest
