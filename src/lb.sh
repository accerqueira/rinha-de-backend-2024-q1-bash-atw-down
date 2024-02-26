#!/usr/bin/env bash

IFS='|' SERVERS=( $SERVERS )

SERVER="${SERVERS[$(( $RANDOM % ${#SERVERS[@]} ))]}"

socat - TCP:${SERVER},connect-timeout=60
# IFS=':' SERVER=( ${SERVER} )
# ncat ${SERVER[@]}
