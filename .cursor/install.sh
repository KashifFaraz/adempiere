#!/usr/bin/env bash
#
# Cloud Agent install script for ADempiere.
#
# Runs once to produce a durable baseline: installs the JDK 8 + Ant toolchain and
# PostgreSQL, builds the application, provisions and seeds the database, and runs
# the ADempiere SilentSetup to generate runtime configuration.
#
# This script is idempotent: it can be re-run safely and will converge to the
# same state (the database import drops and recreates the schema each time).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

JDK8_VERSION="jdk8u452-b09"
JDK8_ARCHIVE_VERSION="8u452b09"
JDK8_DIR="/usr/lib/jvm/${JDK8_VERSION}"
JDK8_URL="https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u452-b09/OpenJDK8U-jdk_x64_linux_hotspot_${JDK8_ARCHIVE_VERSION}.tar.gz"

PG_MAJOR="16"
DB_NAME="adempiere"
DB_USER="adempiere"
DB_PASSWORD="adempiere"
DB_SYSTEM_PASSWORD="postgres"
DB_HOST="localhost"
DB_PORT="5432"

echo "==> Installing system packages (Ant, PostgreSQL) ..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq ant ant-contrib postgresql postgresql-contrib

echo "==> Installing Temurin JDK 8 ..."
if [ ! -d "$JDK8_DIR" ]; then
  tmp_jdk="$(mktemp)"
  curl -fsSL -o "$tmp_jdk" "$JDK8_URL"
  sudo mkdir -p /usr/lib/jvm
  sudo tar -xzf "$tmp_jdk" -C /usr/lib/jvm
  rm -f "$tmp_jdk"
fi
export JAVA_HOME="$JDK8_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
java -version

echo "==> Building ADempiere (ant build) ..."
ant build

ADEMPIERE_HOME="$REPO_ROOT/adempiere/Adempiere"

echo "==> Starting PostgreSQL cluster ..."
sudo pg_ctlcluster "$PG_MAJOR" main start || true
# Wait for PostgreSQL to accept connections.
for _ in $(seq 1 30); do
  if sudo -u postgres pg_isready -q; then break; fi
  sleep 1
done
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '${DB_SYSTEM_PASSWORD}';"

echo "==> Importing ADempiere seed database ..."
cd "$ADEMPIERE_HOME/utils/PostgreSQL"
bash ImportAdempiere.sh PostgreSQL "$DB_HOST" "$DB_PORT" \
  "$DB_USER" "$DB_PASSWORD" postgres "$DB_SYSTEM_PASSWORD" \
  "$DB_NAME" "$DB_NAME" "$DB_NAME" \
  "$ADEMPIERE_HOME/data/Adempiere_pg.dmp" none

echo "==> Writing AdempiereEnv.properties ..."
cat > "$ADEMPIERE_HOME/AdempiereEnv.properties" <<EOF
#AdempiereEnv.properties
ADEMPIERE_HOME=$ADEMPIERE_HOME
JAVA_HOME=$JDK8_DIR
ADEMPIERE_JAVA_TYPE=sun
ADEMPIERE_JAVA_OPTIONS=-Xms64M -Xmx1512M
ADEMPIERE_DB_TYPE=PostgreSQL
ADEMPIERE_DB_PATH=PostgreSQL
ADEMPIERE_DB_SERVER=$DB_HOST
ADEMPIERE_DB_PORT=$DB_PORT
ADEMPIERE_DB_NAME=$DB_NAME
ADEMPIERE_DB_SYSTEM=$DB_SYSTEM_PASSWORD
ADEMPIERE_DB_USER=$DB_USER
ADEMPIERE_DB_PASSWORD=$DB_PASSWORD
ADEMPIERE_APPS_TYPE=tomcat
ADEMPIERE_APPS_SERVER=localhost
ADEMPIERE_JNP_PORT=1099
ADEMPIERE_WEB_PORT=8888
ADEMPIERE_SSL_PORT=4444
ADEMPIERE_KEYSTORE=$ADEMPIERE_HOME/keystore/myKeystore
ADEMPIERE_KEYSTOREWEBALIAS=adempiere
ADEMPIERE_KEYSTORECODEALIAS=adempiere
ADEMPIERE_KEYSTOREPASS=myPassword
ADEMPIERE_CERT_CN=localhost
ADEMPIERE_CERT_ORG=ADempiere Bazaar
ADEMPIERE_CERT_ORG_UNIT=AdempiereUser
ADEMPIERE_CERT_LOCATION=myTown
ADEMPIERE_CERT_STATE=CA
ADEMPIERE_CERT_COUNTRY=US
ADEMPIERE_MAIL_SERVER=localhost
ADEMPIERE_ADMIN_EMAIL=admin@host.com
ADEMPIERE_MAIL_USER=
ADEMPIERE_MAIL_PASSWORD=
ADEMPIERE_FTP_SERVER=localhost
ADEMPIERE_FTP_PREFIX=my
ADEMPIERE_FTP_USER=anonymous
ADEMPIERE_FTP_PASSWORD=user@host.com
EOF

echo "==> Running ADempiere SilentSetup (deploys web apps, signs DB, generates keystore) ..."
cd "$ADEMPIERE_HOME"
export ADEMPIERE_HOME
sh RUN_silentsetup.sh || true  # apps-server connectivity check is expected to warn (Tomcat not running yet)

echo "==> Install complete."
