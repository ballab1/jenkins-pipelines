#!/bin/bash -x

export WORKSPACE='/home/bobb/GIT'

#cd /mnt/k8s/recipes
#tar czf "${WORKSPACE}/recipes.tgz" *
#cd "${WORKSPACE}"
#debugBashScript pipelines/backup.sh "${WORKSPACE}/recipes.tgz"
#rm 'versions.tgz'; rm 'status.groovy'; rm "$(hostname -f).txt"


cd /mnt/k8s/versions
tar czf "${WORKSPACE}/versions.tgz" *
cd "${WORKSPACE}"
debugBashScript pipelines/backup.sh "${WORKSPACE}/versions.tgz"
rm 'versions.tgz'; rm 'status.groovy'; rm "$(hostname -f).txt"
