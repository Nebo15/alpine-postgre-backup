# Alpine PostgreSQL Backups

This is a minimalistic Docker container based on Alpine Linux with [pghoard](https://github.com/ohmu/pghoard) backup utility. It can be deployed to your cluster once and will manage backups for all configured PostgreSQL sites.

Container can be started either in backup or restoration mode, which is set by `PGHOARD_RESTORE_SITE` environment variable. If it's set to a valid host name from `PG_HOSTS` list, it will restore database to the latest available basebackup.

## Installation

Image is available in [nebo15/alpine-postgre-backup Docker Hub](https://hub.docker.com/r/nebo15/alpine-postgre-backup/) repo.

### Environment variables

| VAR_NAME                            | Default Value           | Description |
| ----------------------------------- | ----------------------- | ----------- |
| `PGHOARD_ACTIVE_BACKUP_MODE`        | not set                 | Can be either pg_receivexlog or archive_command. If set to pg_receivexlog, pghoard will start up a pg_receivexlog process to be run against the database server. If archive_command is set, we rely on the user setting the correct archive_command in postgresql.conf. You can also set this to the experimental walreceiver mode whereby pghoard will start communicating directly with PostgreSQL through the replication protocol. (Note requires an unreleased version of psycopg2 library). |
| `PGHOARD_BASEBACKUP_COUNT`          | `2`                     | How many basebackups should be kept around for restoration purposes. The more there are the more diskspace will be used. |
| `PGHOARD_BASEBACKUP_INTERVAL_HOURS` | `24`                    | How often to take a new basebackup of a cluster. The shorter the interval, the faster your recovery will be, but the more CPU/IO usage is required from the servers it takes the basebackup from. If set to a null value basebackups are not automatically taken at all. |
| `PG_HOSTS`                          | not set                 | List of PostgreSQL connections URLs separated by `;`, eg: `postgres://pghoard:secretpassword@host:5432/dbname;postgres://pghoard:secretpassword@other_host:5432/dbname`. For each connection new pghoard backup site will be created. |
| `PGHOARD_STATSD_ADDRESS`            | not set                 | Address or host on which StatsD server accepts metrics. StatsD collection will be disabled if this variable is not set. |
| `PGHOARD_STATSD_PORT`               | `8125`                  | Port on which StatsD server accepts metrics. |
| `PGHOARD_STATSD_FORMAT`             | `datadog`               | Protocol that is supported by StatsD server: [`datadog`](https://github.com/influxdata/telegraf/tree/master/plugins/inputs/statsd) or [`telegraf`](http://docs.datadoghq.com/guides/dogstatsd/#datagram-format). |
| `PGHOARD_LOG_LEVEL`                 | `INFO`                  | Determines log level of `pghoard`. |
| `PGHOARD_STORAGE_TYPE`              | not set                 | Where to store backups? Supported values: `local`, `google`, `s3`, `azure`, `swift`. |

For restoration:

| VAR_NAME                            | Default Value           | Description |
| ----------------------------------- | ----------------------- | ----------- |
| `PGHOARD_RESTORE_SITE`              | not set                 | Host name of a backed-up database. |
| `PGHOARD_ENCRYPTION_PRIVATE_KEY`    | not set                 | Private key to decrypt your backups. Optional. |

Encrypt your backups:

| VAR_NAME                            | Default Value           | Description |
| ----------------------------------- | ----------------------- | ----------- |
| `PGHOARD_ENCRYPTION_KEY_ID`         | not set                 | Name of encryption key. |
| `PGHOARD_ENCRYPTION_PUBLIC_KEY`     | not set                 | Public key to encrypt your backups. |

#### Local storage

| VAR_NAME                     | Default Value  | Description |
| ---------------------------- | -------------- | ----------- |
| `PGHOARD_DIRECTORY`          | not set        | |

#### Amazon S3 storage

| VAR_NAME                     | Default Value  | Description |
| ---------------------------- | -------------- | ----------- |
| `AWS_ACCESS_KEY_ID`          | not set        | |
| `AWS_SECRET_ACCESS_KEY`      | not set        | |
| `AWS_DEFAULT_REGION`         | not set        | |
| `AWS_HOST`                   | not set        | Not required. |
| `AWS_PORT`                   | not set        | Not required. |
| `AWS_IS_SECURE`              | not set        | Not required. |
| `AWS_BUCKETNAME`             | not set        | |

#### Google Cloud Storage

| VAR_NAME                     | Default Value  | Description |
| ---------------------------- | -------------- | ----------- |
| `GCS_PROJECT_ID`             | not set        | ID of a GCS project. |
| `GCS_BUCKET_NAME`            | not set        | Bucket name. |
| `GCS_CREDENTIAL_FILE`        | not set        | Path to the JSON credentials file. Generated in `IAM` -> `Service Accounts`. |

#### OpenStack Swift storage

| VAR_NAME               | Default Value  | Description |
| ---------------------- | -------------- | ----------- |
| `OS_USERNAME`          | not set        | |
| `OS_PASSWORD`          | not set        | |
| `OS_AUTH_URL`          | not set        | |
| `OS_CONTAINER_NAME`    | not set        | |
| `OS_REGION_NAME`       | not set        | Not required. |
| `OS_TENANT_NAME`       | not set        | |

## StatsD

If `PGHOARD_STATSD_ADDRESS` environment variable is set, this container will send meaningful metrics about backups:

- `pghoard.compressed_size_ratio` - (gauge) backups compression ratio.
- `pghoard.last_upload_age` - (gauge) number of seconds since last upload to the storage.
- `pghoard.total_upload_size` - (gauge) total upload volume.
- `pghoard.upload_size` - (rate) size of uploaded backup.
- `pghoard.xlogs_since_basebackup` - (gauge) number of XLogs since last basebackup.

## License

See [LICENSE.md](LICENSE.md).
