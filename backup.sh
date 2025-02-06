#!/bin/bash

set -o errtrace

declare -r TARGET="${1:-}"
declare -r LATEST_CONTENT="${2:?}"

declare -r NODENAME=$(hostname -f)
declare -r WORKSPACE="${WORKSPACE:-$(pwd)}"

source "$(dirname "$0")/backup.bashlib"
main 2>&1 | tee "${WORKSPACE}/${TARGET}.txt"
