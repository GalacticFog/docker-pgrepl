#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
#set -o xtrace

if [[ -z ${1+x} ]]; then
  NAME=""
else 
  NAME="--name $1"
fi

cid=$(docker run -d -P $NAME -e PGREPL_ROLE=PRIMARY galacticfog/postgres_repl)
echo Container ID: $cid
