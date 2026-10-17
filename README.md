# Affinity Answers — Data Engineer Take-Home Solutions

This repository contains verified solutions for the Affinity Answers Data Engineer take-home assessment. Each solution is implemented in modular, tested source files with zero unnecessary frameworks.

---

## Repository Structure

```text
AffinityAnswers/
├── docs/
│   ├── Affinity_Answers_Take_Home_Implementation_Plan.md
│   └── Data Engineer Application Questions.pdf
├── question1_python/
│   ├── product_search.py              # MD Computers search scraper CLI
│   ├── requirements.txt              # Python dependencies
│   ├── README.md                     # Question 1 detailed docs & design decisions
│   └── tests/
│       ├── test_product_search.py    # Unit tests suite (14 tests)
│       └── fixtures/
│           ├── search_results.html   # Authentic saved HTML fixture
│           └── empty_results.html    # Authentic empty search HTML fixture
├── question2_sql/
│   ├── answers.sql                   # Three authoritative, readable SQL solutions
│   ├── requirements.txt              # PyMySQL and cryptography dependencies
│   ├── README.md                     # Rfam schema notes, justifications & verified results
│   ├── run_queries.py                # Cross-platform execution runner
│   └── run_queries.sh                # Shell execution runner wrapper
└── question3_shell/                  # (Question 3: Shell CSV parser - in progress)
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
