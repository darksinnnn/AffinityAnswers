# Question 1: MD Computers Product Search Scraper

A lightweight, robust Python CLI tool that queries MD Computers (`mdcomputers.in`), extracts product listings for a search term, and outputs a structured JSON array.

---

## 1. Design Choices & Decisions

### A. Output Format: JSON Array
- **Standard & Interoperable:** Standard JSON is natively machine-readable, widely supported across programming languages and Unix pipelines (e.g. `jq`), and requires zero third-party dependencies for serialization.
- **Natural Representation:** A single search request returns an ordered list of items, which directly maps to a JSON array of objects.
- **Streamlined Scope:** While JSON Lines (JSONL) is useful for unbounded streams or multi-gigabyte exports, an individual search results page is bounded and compact, making an indented JSON array readable for humans and easy to consume by downstream tools.

### B. Price Extraction & Controlled Normalization
- **Raw Displayed Price (`displayed_price`):** Retains the exact price text rendered on MD Computers (e.g., `"₹10,000 ₹9,160"`), ensuring no information loss.
- **Normalized Old / MRP (`mrp_inr`):** Extracted only when the HTML explicitly marks the element with `<span class="del">` (OpenCart Retrina theme's deleted/strikethrough price).
- **Normalized Selling Price (`selling_price_inr`):** Extracted from `<span class="ins">` (inserted/discounted price) or a single undiscounted `<span class="amount">`.
- **Zero Hallucination / Inference:**
  - We **do not** infer `in_stock` from the presence of an "Add to Cart" button. MD Computers renders cart/interaction buttons across various states, and button presence is not reliable stock proof.
  - We **do not** invent discount percentages; only verified HTML values are extracted.
  - If a product card lacks a price, it is retained with `null` price fields rather than being silently dropped.

### C. Live DOM Verification vs. Blind Assumptions
A live inspection of the actual rendered HTML of MD Computers revealed that the site runs a custom OpenCart theme ("Retrina") rather than default OpenCart templates:
- Generic classes like `.product-thumb`, `.product-layout`, or `#content .product-grid` do **not** exist in the markup.
- The genuine search result container is: `<div class="row all-product-wrapper mb-5">` inside `#content`.
- Product cards are structured as `<div class="retrinapro-productlist-all_products_design">` (with inner `<div class="product-grid-item">`).
- Titles and URLs live inside `<h3 class="product-entities-title"><a href="...">...</a></h3>`.
- Prices live inside `<span class="price">`.

### D. Distinguishing Empty Results from Site Breakages
- An **empty search result** (e.g. searching for a non-existent product) still renders the search filter form (`#input-search`) and heading (`Products meeting the search criteria`), but omits the `.all-product-wrapper` container. The scraper detects this and returns `[]`.
- An **unexpected layout** (e.g., altered markup, server error page, or bot challenge) does not match the search template and raises `ScraperParsingError`, warning the caller on `stderr` and exiting with a non-zero exit code instead of silently pretending zero items were found.
- **Cloudflare Challenges:** Detects bot challenge signatures (e.g. "Attention Required! | Cloudflare") and explicitly reports the block.

### E. Clean Canonical URLs & Proper Parameter Encoding
- Hardcoded URLs and documentation use canonical endpoints (`https://mdcomputers.in/`) without tracking query parameters (`utm_source=chatgpt.com`).
- Search requests are constructed using `requests`' `params` dictionary (`{"route": "product/search", "search": term}`), which automatically handles RFC-compliant URL encoding for spaces, ampersands, and special characters.
- Relative links (e.g., `/product/...`) are safely converted to absolute URLs via `urllib.parse.urljoin`.

---

## 2. Project Structure

```text
question1_python/
├── product_search.py              # Main CLI scraper implementation
├── requirements.txt              # Minimal external dependencies (requests, beautifulsoup4)
├── README.md                     # Documentation, design choices, and verification notes
└── tests/
    ├── test_product_search.py    # 15 standard-library unit tests
    └── fixtures/
        ├── search_results.html   # Authentic saved HTML fixture (18 products)
        └── empty_results.html    # Authentic saved empty search HTML fixture
```

---

## 3. Installation & Dependencies

Requires Python 3.8+:

```bash
pip install -r question1_python/requirements.txt
```

---

## 4. Usage

Run the CLI by passing the search term as a quoted positional argument:

```bash
# Multi-word search
python question1_python/product_search.py "external hard drives"

# Specific model search
python question1_python/product_search.py "4TB-HDD"

# Set a custom timeout (default is 15 seconds)
python question1_python/product_search.py "RTX 4070" --timeout 20
```

### Example JSON Output

```json
[
  {
    "name": "Seagate Expansion 1TB External Hard Drive",
    "url": "https://mdcomputers.in/product/seagate-expansion-1tb-external-hard-drive-stkm1000400",
    "displayed_price": "₹10,000 ₹9,160",
    "mrp_inr": 10000,
    "selling_price_inr": 9160
  },
  {
    "name": "WD Elements 1TB External Hard Drive",
    "url": "https://mdcomputers.in/product/wd-elements-1tb-external-hard-drive-wdbhhg0010bbk-eesn",
    "displayed_price": "₹14,000 ₹9,280",
    "mrp_inr": 14000,
    "selling_price_inr": 9280
  }
]
```

---

## 5. Automated Tests

The test suite runs using Python's built-in `unittest` module and uses local HTML fixtures and mocks so tests do not depend on internet connectivity or live site stability.

### Running the Test Suite

```bash
python -m unittest discover question1_python/tests
```

### Test Coverage Summary (15 Tests)

1. `test_parse_real_fixture_products`: Confirms all 18 products from the authentic MD Computers HTML fixture are parsed with exact names, absolute URLs, displayed prices, and normalized MRP/selling prices.
2. `test_parse_empty_results_fixture`: Confirms authentic empty search HTML produces an empty list `[]`.
3. `test_wrapper_with_unrecognized_cards_raises_error`: Validates that when a product wrapper is present but contains no recognized product card selectors, `ScraperParsingError` is raised instead of silently returning `[]`.
4. `test_missing_price_does_not_drop_product`: Verifies that a product without a price tag retains its record with `null` price fields.
5. `test_single_undiscounted_price`: Verifies undiscounted single price elements extract `selling_price_inr` with `mrp_inr = null`.
6. `test_unexpected_html_structure_raises_error`: Validates that altered markup raises `ScraperParsingError` instead of falsely reporting 0 items.
7. `test_cloudflare_block_page_raises_error`: Validates explicit detection and reporting of bot mitigation challenge pages.
8. `test_relative_url_resolved_to_absolute`: Checks `urljoin` resolution against site base URL.
9. `test_thumbnail_image_link_fallback`: Ensures image thumbnail links are used if title link is missing.
10. `test_clean_numeric_price_helper`: Tests numeric extraction from multiple currency representations (`₹10,000`, `Rs. 1,234.00`, out-of-stock strings).
11. `test_query_parameter_encoding`: Asserts multi-word queries are encoded as query parameters.
12. `test_http_404_failure_raises_error`: Asserts HTTP 404 triggers `ScraperHttpError`.
13. `test_http_500_failure_raises_error`: Asserts HTTP 500 triggers `ScraperHttpError`.
14. `test_network_timeout_raises_error`: Asserts network timeout triggers `ScraperHttpError`.
15. `test_search_products_coordination`: Asserts `search_products` properly chains fetch and parse functions.

---

## 6. Live Smoke Test Results

### Command 1: Multi-word query
```bash
python question1_python/product_search.py "external hard drives"
```
**Result:** HTTP 200 OK, 18 product listings returned.
- First product: `Seagate Expansion 1TB External Hard Drive` (`displayed_price`: `₹10,000 ₹9,160`, `mrp_inr`: `10000`, `selling_price_inr`: `9160`).
- 18th product: `WD My Book 8TB External Hard Drive` (`displayed_price`: `₹30,000 ₹27,199`, `mrp_inr`: `30000`, `selling_price_inr`: `27199`).

### Command 2: Model search
```bash
python question1_python/product_search.py "4TB-HDD"
```
**Result:** HTTP 200 OK, exactly 17 product listings returned, matching live site results.

### Command 3: Non-existent term
```bash
python question1_python/product_search.py "xyznonexistentsearchterm999"
```
**Result:** HTTP 200 OK, returns `[]`.
