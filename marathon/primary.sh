#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
#set -o xtrace

if [[ $# -lt 1 ]]; then 
  echo usage: $0 [marathon-url] [primary-app-id] [primary-vip]
  exit 1
fi

MARURL="$1"
APPID=${2-/gestalt-data/pg1}
VIP=${3-/primary.gestalt-data:5432}

read -r -d '' PAYLOAD <<EOM || true
{
  "env": {
    "POSTGRES_USER": "${POSTGRES_USER-gestaltdev}",
    "POSTGRES_PASSWORD": "${POSTGRES_PASSWORD-letmein}",
    "PGDATA": "/mnt/mesos/sandbox/pgdata",
    "PGREPL_TOKEN": "${PGREPL_TOKEN-wannab3justl1k3u}",
    "PGREPL_ROLE": "PRIMARY"
  },
  "instances": 1,
  "cpus": 1.0,
  "mem": 1024,
  "container": {
    "type": "DOCKER",
    "volumes": [
      {
        "containerPath": "pgdata",
        "mode": "RW",
        "persistent": {
          "size": 100
        }
      }
    ],
    "docker": {
      "image": "galacticfog/postgres_repl:latest",
      "network": "BRIDGE",
      "forcePullImage": true,
      "portMappings": [
        {
          "containerPort": 5432,
          "protocol": "tcp",
          "name": "db",
          "labels": {
            "VIP_0": "$VIP"
          }
        }
      ]
    }
  },
  "healthChecks": [
    {
      "protocol": "COMMAND",
      "command": {
        "value": "gosu postgres pg_ctl status"
      }
    }
  ],
  "taskKillGracePeriodSeconds": 30
}
EOM


echo $PAYLOAD | http PUT $MARURL/v2/apps/$APPID?force=true
