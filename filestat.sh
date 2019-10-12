#!/bin/bash

echo '{'
stat --format='"file name": "%n",' "$(basename "$1")"
echo "\"folder\": \"$( cd "$( dirname "$1" )" && pwd )\","
stat --format='"access rights": "%a",' $1
stat --format='"access rights in human readable form": "%A",' $1
stat --format='"number of blocks allocated": "%b",' $1
stat --format='"the size of each block reported": "%B",' $1
stat --format='"device number": "%d",' $1
stat --format='"device number": "0x%D",' $1
stat --format='"raw mode": "0x%f",' $1
stat --format='"file type": "%F",' $1
stat --format='"owner group": "%g",' $1
stat --format='"owner group name": "%G",' $1
stat --format='"number of hard links": "%h",' $1
stat --format='"inode": "%i",' $1
stat --format='"mount point": "%m",' $1

declare fn="$( stat --printf='%N' $1 )"
fn=${fn//[\xE2\x80\x98\x99]/}
echo "\"file name with dereference if symbolic link\": \"${fn}\","
stat --format='"optimal I/O transfer size hint": "%o",' $1
stat --format='"total size": "%s",' $1
stat --format='"major device type in hex, for character/block device special files": "0x%t",' $1
stat --format='"minor device type in hex, for character/block device special files": "0x%T",' $1
stat --format='"user ID of owner": "%u",' $1
stat --format='"user name of owner": "%U",' $1

declare tob="$(stat --printf='%w' $1)"
[ "$tob" = '-' ] && tob='unknown'
echo "\"time of file birth, human-readable\": \"$tob\","

stat --format='"time of file birth, seconds since Epoch": "%W",' $1
stat --format='"time of last access, human-readable": "%x",' $1
stat --format='"time of last access, seconds since Epoch": "%X",' $1
stat --format='"time of last data modification, human-readable": "%y",' $1
stat --format='"time of last data modification, seconds since Epoch": "%Y",' $1
stat --format='"time of last status change, human-readable": "%z",' $1
stat --format='"time of last status change, seconds since  Epoch": "%Z",' $1

if [ -f $1 ]; then
    declare sha256="$( sha256sum -b $1 | awk '{ print $1 }' )"
    echo "\"sha256\": \"$sha256\""
fi
echo '}'
