#!/usr/bin/env bash

if [ ! -z ${PGREPL_DEBUG+x} ]; then
  set -o xtrace
fi
set -o nounset
set -o pipefail
set -o errexit

PGREPL_ROLE=${PGREPL_ROLE-(none)}
echo "****** PGREPL_ROLE is: $PGREPL_ROLE"

PGREPL_TOKEN=${PGREPL_TOKEN-abc123}
PGREPL_TOKEN_HASH=$(echo $PGREPL_TOKEN | md5sum | awk '{print $1}')

trigger_file="$PGDATA"/pgrepl_trigger
recovery_file="$PGDATA"/recovery.conf
sentinel_file="$PGDATA"/pgrepl_sentinel

initialize_replication() {
  echo "****** Setting postgres system variables for replication"
  gosu postgres postgres --single <<- EOSQL
    ALTER SYSTEM SET wal_level=hot_standby;
    ALTER SYSTEM SET max_wal_senders=10; 
    ALTER SYSTEM SET hot_standby=on;
    CREATE USER pgrepl WITH replication password '${PGREPL_TOKEN_HASH}';
EOSQL
  
  echo "host  replication     pgrepl     0.0.0.0/0         md5" >> "$PGDATA"/pg_hba.conf
}

setup_standby() {
  if [ -z "$PGREPL_MASTER_IP" ]; then
      PGREPL_MASTER_IP=$POSTGRES_PORT_5432_TCP_ADDR
  fi
  if [ -z "$PGREPL_MASTER_PORT" ]; then
      PGREPL_MASTER_PORT=$POSTGRES_PORT_5432_TCP_PORT
  fi
  echo "****** Caching pgrepl credentials in .pgpass"
  mkdir -p /home/postgres
  chown -R postgres:postgres /home/postgres
  su -  postgres -c "echo '*:*:*:pgrepl:$PGREPL_TOKEN_HASH' > /home/postgres/.pgpass"
  chown postgres:postgres /home/postgres/.pgpass
  chmod 0600 /home/postgres/.pgpass
  
  rm -rf "$PGDATA"/*
  echo "****** Catchup with master using pg_basebackup"
  gosu postgres pg_basebackup -D "$PGDATA"/ -h "$PGREPL_MASTER_IP" -p "$PGREPL_MASTER_PORT" -U pgrepl -P 
  
  if [ -e ${trigger_file} ]; then 
    echo "****** Removing trigger file from pg_basebackup"
    rm -f ${trigger_file}    
  fi

  echo "****** Setting recovery configuration"
  gosu postgres echo "standby_mode='on'"                                                              >> ${recovery_file}
  gosu postgres echo "primary_conninfo='host=$PGREPL_MASTER_IP port=$PGREPL_MASTER_PORT user=pgrepl'" >> ${recovery_file}
  gosu postgres echo "recovery_target_timeline = 'latest'"                                            >> ${recovery_file}
  gosu postgres echo "trigger_file = '$trigger_file'"                                                 >> ${recovery_file}

}

setup_primary() {
  if [ -e ${sentinel_file} ]; then
    echo "****** Sentinel file detected; will create trigger file to trigger promotion."
    touch ${trigger_file}
  fi
}

if [ ! -e ${sentinel_file} ]; then 
  initialize_replication
fi

case "$PGREPL_ROLE" in 
  "STANDBY") 
    setup_standby
    ;;
  *) 
    setup_primary
    ;;
esac

echo "****** Creating sentinel file"
touch ${sentinel_file}
