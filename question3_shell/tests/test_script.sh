#!/usr/bin/env bash
# ==============================================================================
# test_script.sh
# Automated test suite for Question 3: Unix Shell CSV Parser & Sorter
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MAIN_SCRIPT="${PROJECT_ROOT}/question3_shell/sort_companies.sh"
AWK_PARSER="${PROJECT_ROOT}/question3_shell/parse_companies.awk"
FIXTURE_EDGE="${PROJECT_ROOT}/question3_shell/tests/fixtures/edge_cases.csv"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
    local test_name="$1"
    shift
    printf "Running: %s ... " "${test_name}"
    if "$@"; then
        printf "PASSED\n"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf "FAILED\n"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ------------------------------------------------------------------------------
# Test 1: Missing argument error handling
# ------------------------------------------------------------------------------
test_missing_arg() {
    local out
    if out=$("${MAIN_SCRIPT}" 2>&1); then
        return 1
    fi
    [[ "${out}" =~ "Exactly one URL argument is required" ]]
}

# ------------------------------------------------------------------------------
# Test 2: Too many arguments error handling
# ------------------------------------------------------------------------------
test_extra_args() {
    local out
    if out=$("${MAIN_SCRIPT}" "https://example.com/a.csv" "https://example.com/b.csv" 2>&1); then
        return 1
    fi
    [[ "${out}" =~ "Exactly one URL argument is required" ]]
}

# ------------------------------------------------------------------------------
# Test 3: Invalid URL protocol scheme
# ------------------------------------------------------------------------------
test_invalid_scheme() {
    local out
    if out=$("${MAIN_SCRIPT}" "ftp://example.com/data.csv" 2>&1); then
        return 1
    fi
    [[ "${out}" =~ "Only HTTP and HTTPS URLs are supported" ]]
}

# ------------------------------------------------------------------------------
# Test 4: HTTP 404 download failure handling
# ------------------------------------------------------------------------------
test_http_failure() {
    local out
    if out=$("${MAIN_SCRIPT}" "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/nonexistent_file_404.csv" 2>&1); then
        return 1
    fi
    [[ "${out}" =~ "Failed to download CSV" ]]
}

# ------------------------------------------------------------------------------
# Test 5: Malformed CSV header detection
# ------------------------------------------------------------------------------
test_malformed_header() {
    local tmp_bad
    tmp_bad="$(mktemp "${TMPDIR:-/tmp}/bad_header.XXXXXX.csv")"
    echo "ID,Name,Description,Amount" > "${tmp_bad}"
    echo "1,Test,Desc,100" >> "${tmp_bad}"

    local err_out
    set +e
    err_out=$(awk -f "${AWK_PARSER}" "${tmp_bad}" 2>&1 >/dev/null)
    local exit_code=$?
    set -e
    rm -f "${tmp_bad}"

    [[ ${exit_code} -ne 0 ]] && [[ "${err_out}" =~ "missing required columns" ]]
}

# ------------------------------------------------------------------------------
# Test 6: Parsing edge cases fixture (quotes, commas, compound years, missing years)
# ------------------------------------------------------------------------------
test_edge_cases_fixture() {
    local parsed_output
    parsed_output=$(awk -f "${AWK_PARSER}" "${FIXTURE_EDGE}" | sort -t$'\t' -k1,1n -k2,2n -k3,3 | cut -f3-5)

    # 1. Quoted commas in company name preserved
    if ! echo "${parsed_output}" | grep -Fq $'Block, Inc.\tOakland, California\t2009'; then
        echo "Failed to preserve comma in company name 'Block, Inc.'" >&2
        return 1
    fi

    # 2. Quoted commas in headquarters location preserved
    if ! echo "${parsed_output}" | grep -Fq $'Abbott Laboratories\tNorth Chicago, Illinois\t1888'; then
        echo "Failed to preserve comma in location 'North Chicago, Illinois'" >&2
        return 1
    fi

    # 3. Both company name and location containing commas
    if ! echo "${parsed_output}" | grep -Fq $'Alpha, Bravo & Charlie, Inc.\tSaint Paul, Minnesota\t1950'; then
        echo "Failed on multiple quoted comma fields" >&2
        return 1
    fi

    # 4. Escaped quotes unescaped cleanly
    if ! echo "${parsed_output}" | grep -Fq $'Company with "Super" Brand, LLC\tAustin, Texas\t2010'; then
        echo "Failed on unescaping double quotes" >&2
        return 1
    fi

    # 5. Compound year '2013 (1888)' parsed as 2013
    if ! echo "${parsed_output}" | grep -Fq $'AbbVie\tNorth Chicago, Illinois\t2013'; then
        echo "Failed to parse compound year '2013 (1888)' as 2013" >&2
        return 1
    fi

    # 6. Slash-separated compound year '1904/1946/1959' parsed as 1904
    if ! echo "${parsed_output}" | grep -Fq $'Xyratex Inc\tSan Jose, California\t1904'; then
        echo "Failed to parse '1904/1946/1959' as 1904" >&2
        return 1
    fi

    # 7. Deterministic tie-breaker for identical year 2013 (AbbVie before Zeta Corp)
    local line_abbvie line_zeta
    line_abbvie=$(echo "${parsed_output}" | grep -n "AbbVie" | cut -d: -f1)
    line_zeta=$(echo "${parsed_output}" | grep -n "Zeta Corp" | cut -d: -f1)
    if [ "${line_abbvie}" -ge "${line_zeta}" ]; then
        echo "Tie-breaker failed: AbbVie (line ${line_abbvie}) should precede Zeta Corp (line ${line_zeta})" >&2
        return 1
    fi

    # 8. Missing and unparseable years sort last
    local last_two
    last_two=$(echo "${parsed_output}" | tail -n 2)
    if ! echo "${last_two}" | grep -Fq $'No Year Corp\tNew York, New York\t'; then
        echo "Missing year was not placed last" >&2
        return 1
    fi
    if ! echo "${last_two}" | grep -Fq $'Text Year Ltd\tWilmington, Delaware\t'; then
        echo "Unparseable year was not placed last" >&2
        return 1
    fi

    # 9. All 11 input records accounted for (no rows dropped)
    local row_count
    row_count=$(echo "${parsed_output}" | wc -l)
    if [ "${row_count}" -ne 11 ]; then
        echo "Expected 11 rows from fixture, found ${row_count}" >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Test 7: Live CSV Smoke Test against actual dataset URL
# ------------------------------------------------------------------------------
test_live_smoke() {
    local live_url="https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv"
    local raw_tmp
    raw_tmp="$(mktemp "${TMPDIR:-/tmp}/live_source.XXXXXX.csv")"
    if ! curl -fsSL --max-time 30 --retry 2 "${live_url}" -o "${raw_tmp}"; then
        echo "Failed to download live source CSV for comparison" >&2
        rm -f "${raw_tmp}"
        return 1
    fi

    # Count source data records (excluding header row and any blank lines)
    local expected_records
    expected_records=$(awk 'NR > 1 && $0 !~ /^[[:space:]]*$/ { c++ } END { print c + 0 }' "${raw_tmp}")
    rm -f "${raw_tmp}"

    local live_out
    live_out=$("${MAIN_SCRIPT}" "${live_url}")

    # Check header
    local header
    header=$(echo "${live_out}" | head -n 1)
    if [ "${header}" != $'Company Name\tLocation\tFounding Year' ]; then
        echo "Unexpected header: ${header}" >&2
        return 1
    fi

    # Count processed data records (excluding header and blank lines)
    local processed_records
    processed_records=$(echo "${live_out}" | awk 'NR > 1 && $0 !~ /^[[:space:]]*$/ { c++ } END { print c + 0 }')

    if [ "${processed_records}" -ne "${expected_records}" ]; then
        echo "Record count mismatch: processed ${processed_records} records, but source has ${expected_records} records" >&2
        return 1
    fi

    # Check that oldest company is State Street Corporation (1792)
    local first_data_row
    first_data_row=$(echo "${live_out}" | sed -n '2p')
    if [[ ! "${first_data_row}" =~ "State Street Corporation" ]]; then
        echo "Oldest company expected State Street Corporation, got: ${first_data_row}" >&2
        return 1
    fi

    # Check that AbbVie compound year is extracted as 2013
    if ! echo "${live_out}" | grep -Fq $'AbbVie\tNorth Chicago, Illinois\t2013'; then
        echo "AbbVie compound year was not extracted as 2013 in live output" >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Execute Suite
# ------------------------------------------------------------------------------
echo "===================================================================="
echo "Question 3: Automated Test Suite"
echo "===================================================================="

run_test "Missing argument error handling" test_missing_arg
run_test "Extra argument error handling" test_extra_args
run_test "Invalid URL protocol scheme" test_invalid_scheme
run_test "HTTP 404 download failure handling" test_http_failure
run_test "Malformed CSV header detection" test_malformed_header
run_test "Edge cases fixture (quotes, commas, years, sorting)" test_edge_cases_fixture
run_test "Live S&P 500 CSV smoke test" test_live_smoke

echo "===================================================================="
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "===================================================================="

if [ "${FAIL_COUNT}" -ne 0 ]; then
    exit 1
fi
