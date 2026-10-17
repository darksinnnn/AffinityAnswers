# ==============================================================================
# parse_companies.awk
# Quote-aware CSV parser and extractor for company constituents data.
# ==============================================================================
# Features:
#   - RFC-4180 quote awareness: correctly preserves commas inside double quotes
#     and handles escaped double quotes ("") without external dependencies.
#   - Dynamic header mapping: locates columns by header name ('Security',
#     'Headquarters Location', 'Founded') rather than rigid numeric column index.
#   - Extracts first 4-digit founding year (e.g. '2013 (1888)' -> 2013).
#   - Outputs intermediate sort keys to allow numeric ascending sorting with
#     missing/unparseable years placed last.
# ==============================================================================

function parse_csv_line(line, fields,    len, c, in_quotes, field_idx, val, i) {
    len = length(line)
    in_quotes = 0
    field_idx = 1
    val = ""

    for (i = 1; i <= len; i++) {
        c = substr(line, i, 1)

        if (in_quotes) {
            if (c == "\"") {
                # Lookahead for escaped quote ("")
                if (i < len && substr(line, i + 1, 1) == "\"") {
                    val = val "\""
                    i++  # skip second quote
                } else {
                    in_quotes = 0
                }
            } else {
                val = val c
            }
        } else {
            if (c == "\"") {
                in_quotes = 1
            } else if (c == ",") {
                fields[field_idx++] = val
                val = ""
            } else {
                val = val c
            }
        }
    }
    fields[field_idx] = val
    return field_idx
}

BEGIN {
    FS = "\n"  # Process entire physical lines
    sec_col = 0
    loc_col = 0
    fnd_col = 0
}

# Header row: dynamically resolve column indices by header name
NR == 1 {
    # Strip trailing CR (\r) from Windows/DOS line endings
    sub(/\r$/, "", $0)

    num_fields = parse_csv_line($0, headers)
    for (i = 1; i <= num_fields; i++) {
        hdr = tolower(headers[i])
        # Clean potential surrounding spaces or quotes
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", hdr)

        if (hdr == "security" || hdr == "company" || hdr == "company name") {
            sec_col = i
        } else if (hdr == "headquarters location" || hdr == "location" || hdr == "headquarters") {
            loc_col = i
        } else if (hdr == "founded" || hdr == "founding year") {
            fnd_col = i
        }
    }

    if (sec_col == 0 || loc_col == 0 || fnd_col == 0) {
        printf "Error: CSV header missing required columns (Security, Headquarters Location, Founded).\n" > "/dev/stderr"
        printf "Found headers: %s\n", $0 > "/dev/stderr"
        exit 1
    }
    next
}

# Data rows
{
    sub(/\r$/, "", $0)
    # Skip empty lines
    if ($0 ~ /^[[:space:]]*$/) {
        next
    }

    parse_csv_line($0, fields)

    company  = fields[sec_col]
    location = fields[loc_col]
    raw_year = fields[fnd_col]

    # Clean whitespace
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", company)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", location)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw_year)

    # Extract first 4-digit year (e.g., '2013 (1888)' -> 2013)
    year = ""
    has_year = 1  # 1 denotes missing/unparseable year (sorts last)
    numeric_year = 9999999

    if (match(raw_year, /[0-9]{4}/)) {
        year = substr(raw_year, RSTART, RLENGTH)
        has_year = 0
        numeric_year = year + 0
    }

    # Emit tab-separated intermediate record:
    # 1: has_year (0 for present, 1 for missing)
    # 2: numeric_year (for numeric sort)
    # 3: company (for deterministic alphabetical tie-breaker)
    # 4: location
    # 5: year (display string: actual 4-digit year or empty string)
    printf "%d\t%d\t%s\t%s\t%s\n", has_year, numeric_year, company, location, year
}
