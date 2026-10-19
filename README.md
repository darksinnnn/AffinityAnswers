# Affinity Answers — Data Engineer Take-Home Solutions

This repository contains verified solutions for the Affinity Answers Data Engineer take-home assessment. Each solution is implemented in modular, tested source files with zero unnecessary frameworks.

---

## Repository Structure

```text
AffinityAnswers/
├── question1_python/
│   ├── product_search.py              # MD Computers search scraper CLI
│   ├── requirements.txt              # Python dependencies
│   ├── README.md                     # Question 1 detailed docs & design decisions
│   └── tests/
│       ├── test_product_search.py    # Unit tests suite (15 tests)
│       └── fixtures/
│           ├── search_results.html   # Authentic saved HTML fixture
│           └── empty_results.html    # Authentic empty search HTML fixture
├── question2_sql/
│   ├── answers.sql                   # Three authoritative, readable SQL solutions
│   ├── requirements.txt              # PyMySQL and cryptography dependencies
│   ├── README.md                     # Rfam schema notes, justifications & verified results
│   ├── run_queries.py                # Cross-platform execution runner
│   └── run_queries.sh                # Shell execution runner wrapper
└── question3_shell/
    ├── sort_companies.sh             # Main Bash entrypoint script
    ├── parse_companies.awk           # Quote-aware CSV parser and extractor
    ├── README.md                     # Design decisions, assumptions & live results
    └── tests/
        ├── test_script.sh            # Automated test suite (7 tests)
        └── fixtures/
            └── edge_cases.csv        # Edge cases fixture (quotes, commas, years)
```

---

## Question 1: Python Scraper (MD Computers)

### Overview
Extracts listed products from MD Computers (`https://mdcomputers.in`) for any search term. Emits an indented JSON array with product name, absolute URL, displayed price string, and normalized MRP and selling prices when explicitly marked in HTML.

### Key Implementation Decisions
- **Inspected Real Markup:** Scraped via the site's live OpenCart Retrina theme structure (`div.all-product-wrapper`, `div.retrinapro-productlist-all_products_design`, `h3.product-entities-title`, `span.price`). Avoids generic assumed selectors like `.product-thumb`.
- **No Hallucinated Data:** Does not infer stock status from the presence of an "Add to Cart" button. Does not guess discount percentages or tax calculations.
- **Defensive Error Handling:** Distinguishes genuine empty search results (`[]`) from bot challenge pages (Cloudflare) or broken layouts (`ScraperParsingError`).
- **Canonical URLs & Proper Query Parameters:** Hardcoded examples use clean canonical URLs without tracking parameters (`utm_source=chatgpt.com`). Query parameters are RFC-encoded via `requests`.

### Quick Run

```bash
# Install dependencies
pip install -r question1_python/requirements.txt

# Run a search
python question1_python/product_search.py "external hard drives"

# Run automated tests
python -m unittest discover question1_python/tests
```

---

## Question 2: SQL & Databases (Rfam Public MySQL)

### Overview
SQL queries written and verified against the live read-only public MySQL endpoint (`mysql-rfam-public.ebi.ac.uk:4497`, database `Rfam`, user `rfamro`).

### Verified Live Results
1. **Acacia Species Count:** **326** distinct species records in the genus *Acacia* belonging to the green plants lineage (*Viridiplantae*). Avoids 63 false positive matches caught by broad `%Acacia%` matching (insects, fungi, rodents).
2. **Longest Wheat DNA Sequence:** ***Triticum durum* (durum wheat)**, accession **`LT934116.1`**, sequence length **`836,514,780` bp** (chromosome 5B assembly). Avoids 58 false positive matches caught by broad `%wheat%` matching (buckwheat, viruses, pests, birds).
3. **Family Pagination (Page 9, 15/page, Max Length > 1,000,000):** Correctly aggregates `MAX(rs.length)` across families, filters with `HAVING MAX(rs.length) > 1000000`, and paginates using `LIMIT 15 OFFSET 120` with deterministic tie-breaker `f.rfam_acc ASC`. Page 9 returns 15 families (accessions `RF01219` through `RF03674`), each with a maximum sequence length of `836,514,780` bp.

### Quick Run

```bash
# Install dependencies (for Python runner)
pip install -r question2_sql/requirements.txt

# Cross-platform Python runner
python question2_sql/run_queries.py

# Or native MySQL CLI
mysql -h mysql-rfam-public.ebi.ac.uk -P 4497 -u rfamro Rfam < question2_sql/answers.sql
```

---

## Question 3: Unix Shell CSV Parser & Sorter (S&P 500)

### Overview
A robust, quote-aware Unix Bash + AWK script that downloads the S&P 500 company constituents dataset, dynamically maps headers, extracts the legal founding year (e.g. resolving `2013 (1888)` to `2013`), and outputs a clean tab-separated dataset sorted numerically by founding year in ascending order.

### Key Implementation Decisions
- **Quote-Aware CSV Parsing:** Implements a quote-aware parser for the verified line-oriented source that handles quoted commas and escaped quotes (`""`), but not quoted multiline fields. Avoids naive `awk -F,` or `cut -d,` field shifting where 13 company names (e.g. `Block, Inc.`) and headquarters locations contain commas.
- **Dynamic Header Mapping:** Locates `Security`, `Headquarters Location`, and `Founded` dynamically by header text rather than relying on brittle column indices.
- **Numeric Year Sorting & Missing Data Handling:** Uses intermediate sort keys so that years are sorted numerically (753 precedes 1888 precedes 2013), ties are broken deterministically by company name, and missing or unparseable years are placed at the very end without fabricating fake dummy years.
- **Ambiguity-Free TSV Output:** Outputs tab-separated records (`Company Name\tLocation\tFounding Year`) so that internal commas in company names or locations never create delimiter ambiguity.

### Quick Run

```bash
# Execute with the canonical assignment URL
./question3_shell/sort_companies.sh "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/refs/heads/main/data/constituents.csv"

# Run automated test suite (7 tests)
./question3_shell/tests/test_script.sh
```

