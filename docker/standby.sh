#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
#set -o xtrace

if [[ $# -lt 1 ]]; then 
  echo usage: $0 [primary-container-id] [standby-container-name]
  exit 1
fi

PRIMARY_CID=${1}
if [[ -z ${2+x} ]]; then
  NAME=""
else 
  NAME="--name $2"
fi

cid=$(docker run -d --link $PRIMARY_CID:postgres -P $NAME -e PGREPL_ROLE=STANDBY  galacticfog/postgres_repl)
echo Container ID: $cid
