#!/usr/bin/env bash

__FILE__="$(readlink -f ${BASH_SOURCE[0]})"
__DIR__="${__FILE__%/*}"

SERVICE=${1:-"${APP:-"${__DIR__}/service.sh"}"}
PORT=${2:-${PORT:-9999}}
WORKERS=${WORKERS:-8}
CONNECTIONS=${CONNECTIONS:-$(( 30 * 220 ))}

set -x
socat TCP-LISTEN:${PORT},reuseaddr,fork,max-children=${WORKERS},backlog=${CONNECTIONS} EXEC:"${SERVICE}"
# socat TCP-LISTEN:${PORT},reuseaddr,fork,max-children=4 EXEC:"${SERVICE}"
# ncat -vvvvv --listen --keep-open --source-port ${PORT} --exec "${SERVICE}"
