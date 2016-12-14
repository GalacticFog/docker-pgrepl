#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
#set -o xtrace

if [[ $# -lt 2 ]]; then 
  echo usage: $0 [marathon-url] [standby-app-id] [standby-vip]
  exit 1
fi

MARURL="$1"
APPID=${2}
if [ $# > 2 ]; then
  NEW_VIP="${3}"
  echo Updating VIP to ${NEW_VIP}
else
  echo Not updating VIP
fi

CURAPP=$(http --check-status $MARURL/v2/apps/$APPID)

if [ -z ${NEW_VIP}+x ]; then 
  PAYLOAD=$(echo $CURAPP | jq ".app | .env.PGREPL_ROLE = \"PRIMARY\" | del(.env.PGREPL_MASTER_IP, .env.PGREPL_MASTER_PORT) | {env}")
else
  PAYLOAD=$(echo $CURAPP | jq ".app | .env.PGREPL_ROLE = \"PRIMARY\" | del(.env.PGREPL_MASTER_IP, .env.PGREPL_MASTER_PORT) | .container.docker.portMappings[0].labels.VIP_0 = \"${NEW_VIP}\" | {env, container}")
fi

echo $PAYLOAD | http PUT $MARURL/v2/apps/$APPID?force=true
