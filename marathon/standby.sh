#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
#set -o xtrace

if [[ $# -lt 2 ]]; then 
  echo usage: $0 [marathon-url] [primary-app-id] [standby-app-id] [standby-vip]
  exit 1
fi

MARURL="$1"
PRIMARY_APPID=${2}
APPID=${3-/gestalt-data/pg2}
VIP=${4-/standby.gestalt-data:5432}

PVIP=$(http $MARURL/v2/apps/$PRIMARY_APPID | jq -r '.app.container.docker.portMappings[0].labels.VIP_0' | sed "s|^/||")
PRIMARY_HOST="${PVIP%:*}.marathon.l4lb.thisdcos.directory"
PRIMARY_PORT="${PVIP#*:}"

PRIMARYAPP=$(http $MARURL/v2/apps/$PRIMARY_APPID)
PHOST=$(echo $PRIMARYAPP | jq -r '.app.tasks[0].host')
PHOSTROLE=$(echo $PRIMARYAPP | jq -r '.app.env.PGREPL_ROLE')
if [ "$PHOSTROLE" != "PRIMARY" ]; then
  echo "WARNING: Specified primary app id was not primary; had PGREPL_ROLE: $PHOSTROLE"
fi
echo Primary VIP is $PRIMARY_HOST:$PRIMARY_PORT

if [[ -z ${PGREPL_DISK_SIZE+x} ]]; then 
  DISK_SIZE=100
else 
  DISK_SIZE=$(echo $PRIMARYAPP | jq -r '.app.container.volumes[0].persistent.size')
fi

read -r -d '' PAYLOAD <<EOM || true
{
  "env": {
    "POSTGRES_USER": "${POSTGRES_USER-gestaltdev}",
    "POSTGRES_PASSWORD": "${POSTGRES_PASSWORD-letmein}",
    "PGDATA": "/mnt/mesos/sandbox/pgdata",
    "PGREPL_TOKEN": "${PGREPL_TOKEN-wannab3justl1k3u}",
    "PGREPL_ROLE": "STANDBY",
    "PGREPL_MASTER_IP": "$PRIMARY_HOST",
    "PGREPL_MASTER_PORT": "$PRIMARY_PORT"
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
          "size": ${DISK_SIZE}
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
  "taskKillGracePeriodSeconds": 30,
  "constraints": [ [ "hostname", "UNLIKE", "$PHOST" ] ]
}
EOM

echo $PAYLOAD | http PUT $MARURL/v2/apps/$APPID?force=true
