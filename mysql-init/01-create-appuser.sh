#!/bin/bash
# Create the application user the microservices use, and grant access to
# the application database. Runs ONCE on first MySQL container start
# (because mysql:8.0 only processes /docker-entrypoint-initdb.d on a
# fresh data dir).
#
# Pre-creating appuser here means the per-service db-init.sh containers
# skip the user-creation step (idempotent on "user exists"). Avoids
# passing root MySQL creds into the long-lived MS containers.
#
# The MYSQL_DATABASE env var on the mysql service already creates the
# database; we only need the user + grants here.
#
# This is a .sh (not .sql) so it can read ${MYSQL_APPUSER} /
# ${MYSQL_APP_PASSWORD} from the compose env — MySQL's docker-entrypoint
# runs/sources .sh files in initdb.d after MySQL is up, but pipes .sql
# files through the mysql client raw with no shell interpolation.

set -e

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<EOSQL
CREATE USER IF NOT EXISTS '${MYSQL_APPUSER}'@'%' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_APPUSER}'@'%';
FLUSH PRIVILEGES;
EOSQL
