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
├── question2_sql/                    # (Question 2: Rfam SQL - in progress)
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
