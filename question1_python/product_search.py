#!/usr/bin/env python3
"""
MD Computers Product Search Scraper
===================================
A CLI tool to search for hardware products on MD Computers (mdcomputers.in),
parse search result listings, and output structured product records as a JSON array.

Usage:
    python product_search.py "external hard drives"
    python product_search.py "RTX 4070"
"""

import argparse
import json
import re
import sys
from typing import Any, Dict, List, Optional, Union
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup


# Canonical base URL for MD Computers (no tracking query parameters)
BASE_URL = "https://mdcomputers.in"

# Default request headers mimicking a modern desktop browser.
# Note: Accept-Encoding is omitted so requests can automatically negotiate
# and decompress gzip/deflate using Python's standard library.
DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}


class ScraperError(Exception):
    """Base exception for MD Computers scraper errors."""
    pass


class ScraperHttpError(ScraperError):
    """Raised when an HTTP network error or unsuccessful status code occurs."""
    pass


class ScraperParsingError(ScraperError):
    """Raised when the HTML structure is missing expected search containers."""
    pass


def clean_numeric_price(price_str: Optional[str]) -> Optional[Union[int, float]]:
    """
    Extract a numeric currency amount from a price string.

    Args:
        price_str: Raw price string, e.g. '₹10,000' or 'Rs. 9,160.50'

    Returns:
        Integer or float representation of the price, or None if unparseable.
    """
    if not price_str:
        return None
    match = re.search(r"(\d[\d,]*\.?\d*)", price_str)
    if not match:
        return None
    cleaned = match.group(1).replace(",", "")
    try:
        val = float(cleaned)
        return int(val) if val.is_integer() else val
    except (ValueError, TypeError):
        return None


def fetch_search_page(
    search_term: str,
    timeout: int = 15,
    session: Optional[requests.Session] = None,
    base_url: str = BASE_URL,
) -> str:
    """
    Fetch the search results HTML from MD Computers using encoded query parameters.

    Args:
        search_term: The search phrase provided by the user.
        timeout: Maximum seconds to wait for HTTP response.
        session: Optional requests.Session instance (useful for testing or connection reuse).
        base_url: Base site URL.

    Returns:
        The raw HTML response body as a string.

    Raises:
        ScraperHttpError: If network request fails or HTTP status is not 200 OK.
    """
    search_url = f"{base_url.rstrip('/')}/"
    # Route and search parameters are passed as a dictionary so requests handles
    # RFC-compliant URL query parameter encoding (spaces -> +, special characters escaped).
    params = {
        "route": "product/search",
        "search": search_term,
    }

    client = session or requests

    try:
        response = client.get(
            search_url,
            params=params,
            headers=DEFAULT_HEADERS,
            timeout=timeout,
        )
        response.raise_for_status()
        return response.text
    except requests.exceptions.RequestException as exc:
        raise ScraperHttpError(f"Failed to fetch search results for '{search_term}': {exc}") from exc


def parse_search_results(
    html_content: str,
    base_url: str = BASE_URL,
) -> List[Dict[str, Any]]:
    """
    Parse MD Computers search page HTML and extract product details.

    Verification note:
        Inspected live HTML reveals MD Computers uses the 'Retrina' OpenCart theme.
        Search results are placed inside `#content` within a `<div class="all-product-wrapper">`
        container. Product cards are rendered in `<div class="retrinapro-productlist-all_products_design">`.
        Titles are in `<h3 class="product-entities-title"><a ...></a></h3>`.
        Prices are in `<span class="price">`, with `<span class="del">` for old/MRP
        price and `<span class="ins">` for special/selling price.

    Args:
        html_content: Raw HTML text of the page.
        base_url: Canonical base URL for resolving relative links.

    Returns:
        A list of dictionaries representing products.

    Raises:
        ScraperParsingError: If expected search page layout elements are absent
                             (distinguishing layout changes or bot blocks from empty results).
    """
    soup = BeautifulSoup(html_content, "html.parser")

    # 1. Check for access blocks or bot challenges (e.g., Cloudflare)
    page_title = soup.title.get_text(strip=True) if soup.title else ""
    if any(keyword in page_title.lower() for keyword in ["cloudflare", "attention required", "just a moment"]):
        raise ScraperParsingError(
            f"Site access blocker or bot challenge encountered: '{page_title}'"
        )

    # 2. Structural sanity check: verify this is an MD Computers search page
    content_area = soup.find(id="content")
    has_search_input = soup.find("input", id="input-search") is not None
    has_search_heading = bool(
        soup.find(
            lambda tag: tag.name in ["h1", "h2"]
            and ("search" in tag.get_text(strip=True).lower()
                 or "products meeting the search criteria" in tag.get_text(strip=True).lower())
        )
    )

    if not (content_area and (has_search_input or has_search_heading)):
        raise ScraperParsingError(
            f"Unexpected page layout: unable to locate search results container or search heading. "
            f"Page title: '{page_title}'"
        )

    # 3. Locate product grid container
    wrapper = content_area.find("div", class_="all-product-wrapper")
    if not wrapper:
        # On MD Computers, a valid search with zero matching products renders the search
        # criteria filters and heading, but omits the 'all-product-wrapper' container.
        return []

    # 4. Extract individual product cards
    cards = wrapper.find_all("div", class_="retrinapro-productlist-all_products_design")
    if not cards:
        # Fallback to inner grid item wrappers if outer layout class changes
        cards = wrapper.find_all("div", class_="product-grid-item")
        if not cards:
            cards = wrapper.find_all("div", class_="product-wrapper")

    if not cards:
        raise ScraperParsingError(
            "Product wrapper container found, but no recognized product cards could be parsed. "
            "Site markup or card selectors may have changed."
        )

    products = []
    for card in cards:
        # Product Name and URL
        title_tag = card.find("h3", class_="product-entities-title")
        name = None
        product_url = None

        if title_tag:
            name = title_tag.get_text(strip=True)
            link_tag = title_tag.find("a")
            if link_tag and link_tag.get("href"):
                product_url = urljoin(base_url, link_tag["href"].strip())

        # Fallback URL from thumbnail link if title link is missing
        if not product_url:
            img_link = card.find("a", class_="product-image-link")
            if img_link and img_link.get("href"):
                product_url = urljoin(base_url, img_link["href"].strip())

        # Price extraction and normalization
        price_tag = card.find("span", class_="price")
        displayed_price: Optional[str] = None
        mrp_inr: Optional[Union[int, float]] = None
        selling_price_inr: Optional[Union[int, float]] = None

        if price_tag:
            displayed_price = price_tag.get_text(separator=" ", strip=True)

            # Check for explicitly identified old (del) and special/selling (ins) prices
            del_tag = price_tag.find("span", class_="del")
            ins_tag = price_tag.find("span", class_="ins")

            if del_tag and ins_tag:
                # Dual-price display: old/MRP is deleted, new selling price is inserted
                mrp_inr = clean_numeric_price(del_tag.get_text(strip=True))
                selling_price_inr = clean_numeric_price(ins_tag.get_text(strip=True))
            elif ins_tag:
                selling_price_inr = clean_numeric_price(ins_tag.get_text(strip=True))
            elif del_tag:
                mrp_inr = clean_numeric_price(del_tag.get_text(strip=True))
            else:
                # Single undiscounted price
                amount_tag = price_tag.find("span", class_="amount")
                raw_amount = amount_tag.get_text(strip=True) if amount_tag else displayed_price
                selling_price_inr = clean_numeric_price(raw_amount)

        # Do not drop products that lack a price; retain the record with null price fields.
        # Notice: we do NOT infer stock status from the presence or absence of an 'Add to Cart' button.
        if name or product_url or displayed_price:
            products.append({
                "name": name,
                "url": product_url,
                "displayed_price": displayed_price,
                "mrp_inr": mrp_inr,
                "selling_price_inr": selling_price_inr,
            })

    return products


def search_products(search_term: str, timeout: int = 15) -> List[Dict[str, Any]]:
    """
    Search MD Computers for products matching a given search term.

    Args:
        search_term: Query phrase (e.g., 'external hard drives').
        timeout: HTTP request timeout in seconds.

    Returns:
        List of product records.
    """
    html = fetch_search_page(search_term, timeout=timeout)
    return parse_search_results(html, base_url=BASE_URL)


def main() -> None:
    """CLI entrypoint."""
    # Ensure stdout handles UTF-8 (e.g. Indian Rupee symbol ₹) cleanly across operating systems
    if sys.platform == "win32" and sys.stdout.encoding != "utf-8":
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except AttributeError:
            pass

    parser = argparse.ArgumentParser(
        description="Extract product information from MD Computers search results.",
    )
    parser.add_argument(
        "search_term",
        type=str,
        help="Search query phrase (e.g., 'external hard drives', 'RTX 4070').",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="Request timeout in seconds (default: 15).",
    )

    args = parser.parse_args()

    try:
        products = search_products(args.search_term, timeout=args.timeout)
        # Emit formatted JSON array to standard output
        print(json.dumps(products, indent=2, ensure_ascii=False))
    except ScraperError as exc:
        sys.stderr.write(f"Error: {exc}\n")
        sys.exit(1)
    except KeyboardInterrupt:
        sys.stderr.write("Search interrupted by user.\n")
        sys.exit(130)


if __name__ == "__main__":
    main()
