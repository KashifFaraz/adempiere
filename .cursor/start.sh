#!/usr/bin/env bash
#
# Cloud Agent start script for ADempiere.
#
# Runs on every boot: starts the PostgreSQL cluster and the ADempiere
# application server (embedded Tomcat). The web UI is served on port 8888
# (http://localhost:8888/webui/).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JDK8_DIR="/usr/lib/jvm/jdk8u452-b09"
PG_MAJOR="16"
ADEMPIERE_HOME="$REPO_ROOT/adempiere/Adempiere"

export JAVA_HOME="$JDK8_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
export ADEMPIERE_HOME

echo "==> Starting PostgreSQL cluster ..."
sudo pg_ctlcluster "$PG_MAJOR" main start || true
for _ in $(seq 1 30); do
  if sudo -u postgres pg_isready -q; then break; fi
  sleep 1
done

if [ ! -d "$ADEMPIERE_HOME" ]; then
  echo "ADempiere is not built yet. Run .cursor/install.sh first." >&2
  exit 1
fi

echo "==> Starting ADempiere application server (Tomcat) ..."
cd "$ADEMPIERE_HOME/utils"
sh RUN_Server2.sh

echo "==> ADempiere server starting. Web UI: http://localhost:8888/webui/"
