# Question 3: Unix Shell CSV Parser & Sorter

A lightweight, quote-aware Unix shell implementation that downloads the S&P 500 company constituents dataset, extracts company names, locations, and founding years, and outputs a clean tab-separated dataset sorted by founding year in ascending order.

---

## 1. Design Choices & Data Engineering Decisions

### A. The Core CSV Trap: Quoted Commas
In naive shell implementations, developers often split fields with `awk -F,` or `cut -d,`. In real-world data like the S&P 500 constituents CSV, this silently corrupts records because commas frequently occur inside quoted fields:
- **Company names with commas:** `Block, Inc.`, `Tesla, Inc.`, `Tapestry, Inc.`, `Rollins, Inc.` (13 companies in the dataset).
- **Headquarters locations with commas:** Almost every location contains a city-state comma, e.g. `"Saint Paul, Minnesota"`, `"North Chicago, Illinois"`.
- **Multiple comma fields per row:** E.g., `ABNB,Airbnb,Consumer Discretionary,"Hotels, Resorts & Cruise Lines","San Francisco, California",...`.

Blind comma splitting shifts subsequent columns, corrupting the `Founded` year column and destroying data integrity.

### B. Quote-Aware AWK Parser vs. Unnecessary Dependencies
Instead of pulling in large external libraries or writing a complex multi-file application, we implemented a pure Unix solution:
1. **Bash Entry Point (`sort_companies.sh`):** Handles CLI argument validation, dependency checking (`curl`, `awk`, `sort`, `mktemp`), download management with redirect handling and finite timeouts, and guaranteed temporary file cleanup via `trap ... EXIT`.
2. **Quote-Aware AWK Parser (`parse_companies.awk`):** Implements an RFC-4180 quote-aware character scanner that:
   - Tracks quote states (`in_quotes`).
   - Treats commas inside quotes as literal field data, not delimiters.
   - Unescapes standard CSV double quotes (`""` -> `"`).
   - Dynamically resolves column positions by header name (`Security`, `Headquarters Location`, `Founded`) rather than hardcoding column numbers.
3. **Line-Oriented Source Verification:**
   Before finalizing the parser, we verified against the live source dataset that each record corresponds to exactly one physical line (504 physical lines for 504 CSV rows, with no embedded line breaks).

### C. Compound Year Extraction & Ordering
- **Compound Years:** Values such as `2013 (1888)` represent spin-offs or reorganizations where the primary year is the legal entity founding year and the parenthetical year is a predecessor. In accordance with dataset documentation, we extract the first 4-digit year (`2013`).
- **Slash Years:** Values such as `1904/1946/1959` extract the initial founding year (`1904`).
- **Missing / Unparseable Years:** If a row lacks a 4-digit year, it is assigned a sort flag (`has_year = 1`) that ensures it sorts **last**, without inventing an arbitrary dummy year.
- **Numeric Ascending Sort with Deterministic Tie-Breaker:**
  - Sorted via `sort -t$'\t' -k1,1n -k2,2n -k3,3`.
  - Column 1: `has_year` (valid years `0` precede missing years `1`).
  - Column 2: Numeric year ascending (`-k2,2n`).
  - Column 3: Company name ascending (`-k3,3`) to deterministically resolve ties when multiple companies share the same founding year.

### D. Output Format: Tab-Separated Values (TSV)
The script emits clean tab-separated output (`TSV`):
```text
Company Name\tLocation\tFounding Year
```
Using tabs prevents any ambiguity with internal commas present in company names (`Block, Inc.`) and headquarters locations (`Oakland, California`).

---

## 2. Project Structure

```text
question3_shell/
├── sort_companies.sh             # Main Bash entrypoint script
├── parse_companies.awk           # Quote-aware CSV parser and extractor
├── README.md                     # Documentation, design decisions & verification
└── tests/
    ├── test_script.sh            # Automated test suite (7 tests)
    └── fixtures/
        └── edge_cases.csv        # Fixture covering quoted commas, compound years, missing years
```

---

## 3. Usage

```bash
# Execute with the canonical assignment URL
./question3_shell/sort_companies.sh "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv"

# View first 20 oldest companies
./question3_shell/sort_companies.sh "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv" | head -n 20
```

*Note for Windows users:* Execute via Git Bash or WSL:
```powershell
& "C:\Program Files\Git\bin\bash.exe" question3_shell/sort_companies.sh "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv"
```

---

## 4. Automated Tests

Run the automated test suite:

```bash
./question3_shell/tests/test_script.sh
```

### Test Coverage (7 Tests)

1. `test_missing_arg`: Confirms missing URL exits non-zero and prints usage instructions.
2. `test_extra_args`: Confirms extra arguments are rejected.
3. `test_invalid_scheme`: Confirms unsupported protocols (e.g. `ftp://`) are rejected.
4. `test_http_failure`: Confirms HTTP 404 download errors fail safely with descriptive stderr message.
5. `test_malformed_header`: Confirms CSVs missing required headers are rejected immediately.
6. `test_edge_cases_fixture`: Confirms edge case handling on `edge_cases.csv`:
   - Quoted commas in company names (`Block, Inc.`) preserved.
   - Quoted commas in locations (`North Chicago, Illinois`) preserved.
   - Escaped quotes (`"Super"`) unescaped correctly.
   - Compound year `2013 (1888)` parsed as `2013`.
   - Compound year `1904/1946/1959` parsed as `1904`.
   - Numeric sorting (753 precedes 1888 precedes 2013).
   - Deterministic tie-breaking (AbbVie precedes Zeta Corp in 2013).
   - Missing and unparseable years placed last.
   - Zero dropped rows (11 input rows -> 11 output rows).
7. `test_live_smoke`: Runs against the live dataset URL and verifies output headers, row count, and oldest/compound records.

---

## 5. Live Smoke Test Results

- **Input URL:** `https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv`
- **Observed Row Count:** Exactly **503 data rows** (504 lines including header). Every input row accounted for.
- **Sample Head (Oldest Companies):**
  ```text
  Company Name	Location	Founding Year
  State Street Corporation	Boston, Massachusetts	1792
  Colgate-Palmolive	New York City, New York	1806
  Hartford (The)	Hartford, Connecticut	1810
  Bunge Global	Chesterfield, Missouri	1818
  Consolidated Edison	New York City, New York	1823
  KeyCorp	Cleveland, Ohio	1825
  Citizens Financial Group	Providence, Rhode Island	1828
  McKesson	Irving, Texas	1833
  Deere & Company	Moline, Illinois	1837
  Procter & Gamble	Cincinnati, Ohio	1837
  ```
- **Sample Tail (Recent Companies):**
  ```text
  Solventum	Saint Paul, Minnesota	2023
  TKO Group Holdings	New York City, New York	2023
  Veralto	Waltham, Massachusetts	2023
  GE Vernova	Cambridge, Massachusetts	2024
  Qnity Electronics	Wilmington, Delaware	2025
  Skydance Corporation	New York City, New York	2025
  Vylor	Johnston, Iowa	2026
  ```
