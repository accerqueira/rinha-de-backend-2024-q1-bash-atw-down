#!/usr/bin/env bash

DEBUG=1


DB_PATH="${PWD}/db.sqlite3"


__FILE__="$(readlink -f ${BASH_SOURCE[0]})"
__DIR__="${__FILE__%/*}"


function tap() {
	local PREFIX="${2}"
	[[ -n "$DEBUG" ]] && tee >(sed "s#^#${2}#" >&2) || cat
	# [[ -n "$DEBUG" ]] && tee >(sed "s#^#${2}#" >> "${1}") || cat
}

function sql() {
	sqlite3 \
		-batch \
		-cmd '.output /dev/null' \
		-cmd 'PRAGMA jounal_mode=WAL;' \
		-cmd 'PRAGMA synchronous=NORMAL;' \
		-cmd 'PRAGMA busy_timeout=5000' \
		-cmd '.timeout 5000' \
		-cmd '.output stdout' \
		"${@}" 2> >(grep -v 'database is locked' >&2)
}

function handle_request() {
	local DB_PATH="${1}"
	sql "${DB_PATH}"
	# tap queries.log "> " | sql "${DB_PATH}" | tap queries.log "< "
}

# handle_request "${DB_PATH}"

# lock_file="/tmp/socat-lock-$(( ( RANDOM % 8 )  + 1 ))"
# touch "$lock_file"
#
# exec 4< "$lock_file"
# flock 4
handle_request "${DB_PATH}"
# exec 4<&-
