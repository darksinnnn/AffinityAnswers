#!/usr/bin/env bash
# ==============================================================================
# sort_companies.sh
# ==============================================================================
# Downloads an S&P 500 company constituents CSV from a specified URL,
# parses company names, headquarters locations, and founding years,
# and outputs them as a clean TSV sorted by founding year in ascending order.
#
# Usage:
#   ./sort_companies.sh <csv-url>
#
# Example:
#   ./sort_companies.sh "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv"
# ==============================================================================

set -euo pipefail

# Print usage message to stderr
usage() {
    cat <<EOF >&2
Usage: $0 <csv-url>

Arguments:
  csv-url    HTTP or HTTPS URL pointing to the company constituents CSV.

Example:
  $0 "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv"
EOF
    exit 1
}

# 1. Validate argument count
if [ "$#" -ne 1 ]; then
    echo "Error: Exactly one URL argument is required. Received $# arguments." >&2
    usage
fi

URL="$1"

# 2. Validate URL protocol
if [[ ! "${URL}" =~ ^https?:// ]]; then
    echo "Error: Invalid URL scheme. Only HTTP and HTTPS URLs are supported." >&2
    echo "Provided: ${URL}" >&2
    exit 1
fi

# 3. Check for required external utilities
for cmd in curl awk sort mktemp cut; do
    if ! command -v "${cmd}" &> /dev/null; then
        echo "Error: Required command '${cmd}' is not installed or not in PATH." >&2
        exit 1
    fi
done

# 4. Locate AWK parsing script relative to this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK_PARSER="${SCRIPT_DIR}/parse_companies.awk"

if [ ! -f "${AWK_PARSER}" ]; then
    echo "Error: AWK parsing script not found at '${AWK_PARSER}'." >&2
    exit 1
fi

# 5. Create secure temporary file with guaranteed cleanup trap
TMP_DIR="${TMPDIR:-/tmp}"
TMP_FILE="$(mktemp "${TMP_DIR}/companies_data.XXXXXX")"
trap 'rm -f "${TMP_FILE}"' EXIT INT TERM

# 6. Download CSV with curl (fail on HTTP error, follow redirects, 30s timeout)
if ! curl -fsSL --max-time 30 --retry 2 "${URL}" -o "${TMP_FILE}"; then
    echo "Error: Failed to download CSV from '${URL}'." >&2
    exit 1
fi

# 7. Sanity check: ensure file is non-empty
if [ ! -s "${TMP_FILE}" ]; then
    echo "Error: Downloaded CSV is empty." >&2
    exit 1
fi

# 8. Output TSV header
printf "Company Name\tLocation\tFounding Year\n"

# 9. Parse with quote-aware AWK, sort numerically with tie-breakers, and format output
#
# Intermediate AWK columns:
#   $1: has_year (0 for present, 1 for missing/unparseable -> missing sort last)
#   $2: numeric_year (e.g. 1784, 1902, 2013 -> sorted numerically)
#   $3: company name (alphabetical deterministic tie-breaker)
#   $4: headquarters location
#   $5: display year (actual 4-digit year or empty string)
#
# Sorting keys:
#   -k1,1n: rows with valid years (0) come before missing (1)
#   -k2,2n: sort years numerically ascending
#   -k3,3 : company name tie-breaker ascending
#
# Cut: extracts columns 3, 4, 5 (Company Name, Location, Founding Year)
awk -f "${AWK_PARSER}" "${TMP_FILE}" \
    | sort -t$'\t' -k1,1n -k2,2n -k3,3 \
    | cut -f3-5
