#!/usr/bin/env bash
# ==============================================================================
# Affinity Answers — Question 2: Rfam SQL Query Runner (Bash)
# ==============================================================================
# Usage:
#   ./run_queries.sh
#
# Requirements:
#   - mysql client CLI OR python3 with pymysql installed
# ==============================================================================

set -euo pipefail

HOST="mysql-rfam-public.ebi.ac.uk"
PORT="4497"
USER="rfamro"
DB="Rfam"
SQL_FILE="$(dirname "$0")/answers.sql"

echo "===================================================================="
echo "Rfam Public MySQL Execution"
echo "Host: ${HOST}:${PORT} | Database: ${DB} | User: ${USER}"
echo "===================================================================="

if command -v mysql &> /dev/null; then
    echo "Using MySQL CLI to execute answers.sql..."
    mysql -h "${HOST}" -P "${PORT}" -u "${USER}" "${DB}" < "${SQL_FILE}"
elif command -v python3 &> /dev/null; then
    echo "MySQL CLI not found; executing via Python runner..."
    python3 "$(dirname "$0")/run_queries.py"
elif command -v python &> /dev/null; then
    echo "MySQL CLI not found; executing via Python runner..."
    python "$(dirname "$0")/run_queries.py"
else
    echo "Error: Neither mysql CLI nor python is available to execute queries." >&2
    exit 1
fi
