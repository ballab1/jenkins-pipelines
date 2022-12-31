#!/bin/bash

if [ -d bin ]; then
    git submodule update --init -- bin
    cd bin
    git fetch --all
    git checkout --detach origin/main
    git-crypt unlock /home/bobb/src/keys/work-stuff.key
    git submodule update --init -- bashlib
    cd bashlib
    git fetch --all
    git checkout --detach origin/main
    cd ../..
fi
exit 0
