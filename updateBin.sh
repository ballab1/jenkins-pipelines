#!/bin/bash

if [ -d bin ]; then
    git submodule update --init -- bin
    cd bin
    git fetch --all
    git checkout --detach origin/master
    git submodule update --init -- bashlib
    cd bashlib
    git fetch --all
    git checkout --detach origin/master
    cd ../..
fi
exit 0
