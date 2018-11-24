#!/bin/bash

set -o errtrace

export TERM=linux
declare results=./results.txt

function onexit()
{
    echo ''
    echo ''
    echo show what was done
    [ ! -e "$results" ] || cat $results
}
trap onexit ERR
trap onexit INT
trap onexit PIPE

echo ''
echo ''
echo get latest updates
sudo /usr/bin/apt-get update -y &>$results

echo ''
echo show what needs done
/usr/lib/update-notifier/apt-check --human-readable
/usr/lib/ubuntu-release-upgrader/check-new-release -c || true

echo ''
echo ''
echo report if we need to reboot and/or run fsck
sudo /usr/bin/apt-get dist-upgrade -y &>>$results
declare -a checks=('/var/lib/update-notifier/fsck-at-reboot' '/var/run/reboot-required')
for fl in "${checks[@]}" ; do
    echo checking $fl
    [ -f $fl ] && cat $fl
done

echo ''
echo ''
echo report our linux installations
dpkg --get-selections | grep 'linux.*-4'

declare installs=$(dpkg --get-selections | grep -e 'linux.*-4' | grep -v `uname -r | sed s/-generic//` | awk '{ print  $1 }' | tr '\n' ' ')
if [[ -n $installs ]]; then
    sudo /usr/bin/apt-get remove -y $installs
    sudo /usr/bin/apt-get purge -y $installs
    sudo /usr/bin/apt-get autoremove -y
    sudo /usr/bin/apt autoremove -y
    echo ''
    echo ''
    echo report our linux installations
    dpkg --get-selections | grep 'linux.*-4'
fi
