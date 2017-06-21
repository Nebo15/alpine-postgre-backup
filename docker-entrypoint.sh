#!/bin/sh
set -e

echo "Resolving backups sites.."
HOSTS_URLS=(${PG_HOSTS//;/ })

echo "Found ${#HOSTS_URLS[@]} PostgreSQL hosts.."

echo "Create pghoard configuration with confd.."
confd -onetime -backend env

echo "Create pghoard directories.."
mkdir -p ${PGDATA}/pghoard
chown -R postgres ${PGDATA}
mkdir -p /var/lib/pghoard
chown -R postgres /var/lib/pghoard

if [ -z "${PGHOARD_RESTORE_SITE}" ]; then
  echo "Starting backup mode.."

  if [[ "${DUMP_CONFIG}" == "true" ]]; then
    echo "Dump configuration.."
    cat ${PGDATA}/pghoard.json
  fi;

  echo "Create physical_replication_slot on master nodes ..."
  for DATABASE_URL in "${HOSTS_URLS[@]}"
  do
    # extract the protocol
    proto="`echo $DATABASE_URL | grep '://' | sed -e's,^\(.*://\).*,\1,g'`"
    # remove the protocol
    url=`echo $DATABASE_URL | sed -e s,$proto,,g`

    # extract the user and password (if any)
    userpass="`echo $url | grep @ | cut -d@ -f1`"
    pass=`echo $userpass | grep : | cut -d: -f2`
    if [ -n "$pass" ]; then
        user=`echo $userpass | grep : | cut -d: -f1`
    else
        user=$userpass
    fi

    # extract the host -- updated
    hostport=`echo $url | sed -e s,$userpass@,,g | cut -d/ -f1`
    port=`echo $hostport | grep : | cut -d: -f2`
    if [ -n "$port" ]; then
        host=`echo $hostport | grep : | cut -d: -f1`
    else
        host=$hostport
    fi

    # extract the path (if any)
    path="`echo $url | grep / | cut -d/ -f2-`"

    echo " - DB host: $host"
    echo "   DB user: $user"
    echo "   DB pass: ****"
    echo "   DB port: $port"
    echo "   DB name: $path"

    export PGPASSWORD=$pass
    until psql -qAt -U $user -h $host -d postgres -c "select user;"; do
      echo "sleep 1s and try again ..."
      sleep 1
    done

    psql -h $host -c "WITH foo AS (SELECT COUNT(*) AS count FROM pg_replication_slots WHERE slot_name='pghoard') SELECT pg_create_physical_replication_slot('pghoard') FROM foo WHERE count=0;" -U $user -d postgres
  done

  echo "Run the pghoard daemon ..."
  su-exec postgres pghoard --short-log --config ${PGDATA}/pghoard.json
else
  echo "Starting restoration mode with opts: "$@

  if [[ "${DUMP_CONFIG}" == "true" ]]; then
    echo "Dump configuration.."
    cat ${PGDATA}/pghoard_restore.json
  fi;

  echo "Set pghoard to maintenance mode"
  touch /tmp/pghoard_maintenance_mode_file

  echo "Listing available basebackups"
  pghoard_restore list-basebackups --config ${PGDATA}/pghoard_restore.json --site $PGHOARD_RESTORE_SITE

  if [[ "${PGHOARD_RECOVERY_BASEBACKUP}" != "" ]]; then
    echo "Recovery to the basebackup ${PGHOARD_RECOVERY_BASEBACKUP}"
    RECOVERY_FLAG="--basebackup ${PGHOARD_RECOVERY_BASEBACKUP}"
  elif [ -z "${PGHOARD_RECOVERY_TARGET_TIME}" ]; then
    echo "Recovery to the transaction XID ${PGHOARD_RECOVERY_TARGET_XID}"
    RECOVERY_FLAG="--recovery-target-xid ${PGHOARD_RECOVERY_TARGET_XID}"
  else
    echo "Recovery to the PITR ${PGHOARD_RECOVERY_TARGET_TIME}"
    RECOVERY_FLAG="--recovery-target-time ${PGHOARD_RECOVERY_TARGET_TIME}"
  fi;

  echo "Starting restoration process"
  su-exec postgres pghoard_restore get-basebackup --config ${PGDATA}/pghoard_restore.json --site $PGHOARD_RESTORE_SITE --target-dir ${PGDATA}/restore --restore-to-master --recovery-target-action shutdown --recovery-end-command "pkill pghoard" --overwrite ${RECOVERY_FLAG}

  ls -la ${PGDATA}/restore

  # remove custom server configuration (especially the hot standby parameter)
  echo "local replication all trust" >> ${PGDATA}/restore/pg_hba.conf
  su-exec postgres mv ${PGDATA}/restore/postgresql.auto.conf ${PGDATA}/restore/postgresql.auto.conf.backup

  echo "Start the pghoard daemon ..."
  su-exec postgres pghoard --short-log --config ${PGDATA}/pghoard_restore.json &

  if [ -z "$RESTORE_CHECK_COMMAND" ]; then
    # Manual mode
    # Just start PostgreSQL
    echo "Start PostgresSQL in daemon mode ..."
    su-exec postgres postgres -D ${PGDATA}/restore &

    sleep 60
  else
    # Automatic test mode
    # Run test commands against PostgreSQL server and exit
    echo "Start PostgresSQL ..."
    su-exec postgres pg_ctl -D ${PGDATA}/restore start

    # Give postgres some time before starting the harassment
    sleep 20

    until su-exec postgres psql -At -c "SELECT * FROM pg_is_in_recovery()" | grep -q f
    do
      sleep 5
      echo "AutoCheck: waiting for restoration to finish..."
    done

    echo "AutoCheck: running command on db..."
    OUT_LINES=$(su-exec postgres psql -c "$RESTORE_CHECK_COMMAND" "$RESTORE_CHECK_DB" | wc -l)
    echo "AutoCheck: $OUT_LINES lines returned"

    if [ $OUT_LINES -gt 0 ]; then
      echo "AutoCheck: SUCCESS"
    else
      echo "AutoCheck: FAILURE"
    fi
  fi

  while :; do echo "INFO. Backup should be ready to be fetched"; sleep 2073600; done
fi
