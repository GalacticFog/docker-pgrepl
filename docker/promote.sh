#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
#set -o xtrace

if [[ $# -lt 1 ]]; then 
  echo usage: $0 [standby-container-id]
  exit 1
fi

CID=${1}
docker exec $1 gosu postgres pg_ctl promote
