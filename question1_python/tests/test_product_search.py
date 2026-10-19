"""
Unit tests for MD Computers Product Search Scraper
==================================================
Tests cover:
- Parsing authentic saved HTML fixtures (multi-product search results)
- Price extraction (dual prices, undiscounted prices, missing prices)
- Empty search results handling
- Layout change detection (unexpected HTML raises ScraperParsingError)
- Bot/Cloudflare block page detection
- URL parameter encoding (spaces, symbols)
- Mocked HTTP failures (404, 500, timeouts, connection errors)
- Absolute URL resolution
"""

import os
import unittest
from unittest.mock import MagicMock, patch
import requests

from question1_python.product_search import (
    BASE_URL,
    ScraperHttpError,
    ScraperParsingError,
    clean_numeric_price,
    fetch_search_page,
    parse_search_results,
    search_products,
)

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


class TestProductSearchParser(unittest.TestCase):
    """Tests for HTML parsing logic."""

    @classmethod
    def setUpClass(cls):
        fixture_path = os.path.join(FIXTURES_DIR, "search_results.html")
        with open(fixture_path, "r", encoding="utf-8") as f:
            cls.search_fixture_html = f.read()

        empty_fixture_path = os.path.join(FIXTURES_DIR, "empty_results.html")
        with open(empty_fixture_path, "r", encoding="utf-8") as f:
            cls.empty_fixture_html = f.read()

    def test_parse_real_fixture_products(self):
        """Verify parser correctly extracts products from real MD Computers HTML fixture."""
        products = parse_search_results(self.search_fixture_html)

        # The saved fixture for 'external hard drives' contains 18 items
        self.assertEqual(len(products), 18)

        # Validate the first item structure and exact extracted values
        first = products[0]
        self.assertEqual(first["name"], "Seagate Expansion 1TB External Hard Drive")
        self.assertEqual(
            first["url"],
            "https://mdcomputers.in/product/seagate-expansion-1tb-external-hard-drive-stkm1000400",
        )
        self.assertIn("₹10,000", first["displayed_price"])
        self.assertIn("₹9,160", first["displayed_price"])
        self.assertEqual(first["mrp_inr"], 10000)
        self.assertEqual(first["selling_price_inr"], 9160)

    def test_parse_empty_results_fixture(self):
        """Verify an authentic empty search results page returns an empty list []."""
        products = parse_search_results(self.empty_fixture_html)
        self.assertIsInstance(products, list)
        self.assertEqual(len(products), 0)

    def test_wrapper_with_unrecognized_cards_raises_error(self):
        """If product wrapper exists but contents match no supported card selectors, raise ScraperParsingError."""
        snippet = """
        <div id="content">
            <input id="input-search" value="gpu"/>
            <div class="row all-product-wrapper mb-5">
                <div class="unrecognized-card-class">
                    <h3 class="custom-title">Unrecognized Format</h3>
                </div>
            </div>
        </div>
        """
        with self.assertRaises(ScraperParsingError) as ctx:
            parse_search_results(snippet)
        self.assertIn("no recognized product cards could be parsed", str(ctx.exception))


    def test_missing_price_does_not_drop_product(self):
        """A product card without price elements should be retained with None price fields."""
        snippet = """
        <div id="content">
            <input id="input-search" value="test"/>
            <div class="row all-product-wrapper mb-5">
                <div class="retrinapro-productlist-all_products_design">
                    <div class="product-wrapper">
                        <h3 class="product-entities-title">
                            <a href="/product/special-unpriced-item">Special Unpriced Hardware</a>
                        </h3>
                    </div>
                </div>
            </div>
        </div>
        """
        products = parse_search_results(snippet)
        self.assertEqual(len(products), 1)
        self.assertEqual(products[0]["name"], "Special Unpriced Hardware")
        self.assertEqual(products[0]["url"], "https://mdcomputers.in/product/special-unpriced-item")
        self.assertIsNone(products[0]["displayed_price"])
        self.assertIsNone(products[0]["mrp_inr"])
        self.assertIsNone(products[0]["selling_price_inr"])

    def test_single_undiscounted_price(self):
        """A product with only a single undiscounted price should extract selling_price_inr with null mrp_inr."""
        snippet = """
        <div id="content">
            <input id="input-search" value="keyboard"/>
            <div class="row all-product-wrapper mb-5">
                <div class="retrinapro-productlist-all_products_design">
                    <div class="product-wrapper">
                        <h3 class="product-entities-title">
                            <a href="https://mdcomputers.in/product/mechanical-keyboard">Mechanical Keyboard</a>
                        </h3>
                        <span class="price">
                            <span class="amount">₹3,499</span>
                        </span>
                    </div>
                </div>
            </div>
        </div>
        """
        products = parse_search_results(snippet)
        self.assertEqual(len(products), 1)
        self.assertEqual(products[0]["name"], "Mechanical Keyboard")
        self.assertEqual(products[0]["displayed_price"], "₹3,499")
        self.assertIsNone(products[0]["mrp_inr"])
        self.assertEqual(products[0]["selling_price_inr"], 3499)

    def test_unexpected_html_structure_raises_error(self):
        """Unexpected markup (e.g. missing search containers or completely altered site) raises ScraperParsingError."""
        broken_html = """
        <!DOCTYPE html>
        <html>
            <head><title>Some Random Page</title></head>
            <body>
                <div class="main-body">
                    <p>Welcome to our homepage!</p>
                </div>
            </body>
        </html>
        """
        with self.assertRaises(ScraperParsingError) as ctx:
            parse_search_results(broken_html)
        self.assertIn("Unexpected page layout", str(ctx.exception))

    def test_cloudflare_block_page_raises_error(self):
        """Bot mitigation / Cloudflare challenge page raises ScraperParsingError with blocker description."""
        cloudflare_html = """
        <!DOCTYPE html>
        <html>
            <head><title>Attention Required! | Cloudflare</title></head>
            <body>
                <h1>Please complete the security check to proceed.</h1>
            </body>
        </html>
        """
        with self.assertRaises(ScraperParsingError) as ctx:
            parse_search_results(cloudflare_html)
        self.assertIn("Site access blocker", str(ctx.exception))

    def test_relative_url_resolved_to_absolute(self):
        """Relative product links should be resolved to absolute URLs using base_url."""
        snippet = """
        <div id="content">
            <input id="input-search" value="cable"/>
            <div class="all-product-wrapper">
                <div class="product-grid-item">
                    <h3 class="product-entities-title">
                        <a href="category/cables/hdmi-cable-2m">HDMI Cable 2M</a>
                    </h3>
                </div>
            </div>
        </div>
        """
        products = parse_search_results(snippet, base_url="https://mdcomputers.in")
        self.assertEqual(len(products), 1)
        self.assertEqual(
            products[0]["url"],
            "https://mdcomputers.in/category/cables/hdmi-cable-2m",
        )

    def test_clean_numeric_price_helper(self):
        """Test clean_numeric_price helper with various formats."""
        self.assertEqual(clean_numeric_price("₹10,000"), 10000)
        self.assertEqual(clean_numeric_price("₹9,160.50"), 9160.5)
        self.assertEqual(clean_numeric_price("Rs. 1,234"), 1234)
        self.assertEqual(clean_numeric_price("Rs. 1,234.00"), 1234)
        self.assertIsNone(clean_numeric_price(None))
        self.assertIsNone(clean_numeric_price(""))
        self.assertIsNone(clean_numeric_price("Out of Stock"))

    def test_thumbnail_image_link_fallback(self):
        """If title element has no anchor tag, fallback to image link."""
        snippet = """
        <div id="content">
            <input id="input-search" value="gpu"/>
            <div class="all-product-wrapper">
                <div class="product-grid-item">
                    <a class="product-image-link" href="/product/rtx-5090"></a>
                    <h3 class="product-entities-title">Nvidia RTX 5090</h3>
                </div>
            </div>
        </div>
        """
        products = parse_search_results(snippet, base_url="https://mdcomputers.in")
        self.assertEqual(len(products), 1)
        self.assertEqual(products[0]["name"], "Nvidia RTX 5090")
        self.assertEqual(products[0]["url"], "https://mdcomputers.in/product/rtx-5090")


class TestProductSearchHttp(unittest.TestCase):
    """Tests for HTTP fetching, parameter encoding, and error handling."""

    @patch("requests.get")
    def test_query_parameter_encoding(self, mock_get):
        """Multi-word queries and special characters should be passed via params dictionary."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.text = "<html><head><title>Search - external hard drives</title></head><div id='content'><input id='input-search'/></div></html>"
        mock_get.return_value = mock_response

        fetch_search_page("external hard drives")

        mock_get.assert_called_once()
        _, kwargs = mock_get.call_args
        self.assertIn("params", kwargs)
        self.assertEqual(kwargs["params"]["route"], "product/search")
        self.assertEqual(kwargs["params"]["search"], "external hard drives")

    @patch("requests.get")
    def test_http_404_failure_raises_error(self, mock_get):
        """HTTP 404 response should raise ScraperHttpError."""
        mock_response = MagicMock()
        mock_response.raise_for_status.side_effect = requests.exceptions.HTTPError("404 Not Found")
        mock_get.return_value = mock_response

        with self.assertRaises(ScraperHttpError) as ctx:
            fetch_search_page("bad-endpoint")
        self.assertIn("Failed to fetch search results", str(ctx.exception))

    @patch("requests.get")
    def test_http_500_failure_raises_error(self, mock_get):
        """HTTP 500 response should raise ScraperHttpError."""
        mock_response = MagicMock()
        mock_response.raise_for_status.side_effect = requests.exceptions.HTTPError("500 Server Error")
        mock_get.return_value = mock_response

        with self.assertRaises(ScraperHttpError):
            fetch_search_page("server-error")

    @patch("requests.get")
    def test_network_timeout_raises_error(self, mock_get):
        """Network timeout should raise ScraperHttpError."""
        mock_get.side_effect = requests.exceptions.Timeout("Connection timed out")

        with self.assertRaises(ScraperHttpError) as ctx:
            fetch_search_page("timeout-term")
        self.assertIn("Connection timed out", str(ctx.exception))

    @patch("question1_python.product_search.fetch_search_page")
    @patch("question1_python.product_search.parse_search_results")
    def test_search_products_coordination(self, mock_parse, mock_fetch):
        """search_products coordinates fetch and parse functions."""
        mock_fetch.return_value = "<html>mock html</html>"
        mock_parse.return_value = [{"name": "Mock Product"}]

        results = search_products("test term")
        mock_fetch.assert_called_once_with("test term", timeout=15)
        mock_parse.assert_called_once_with("<html>mock html</html>", base_url=BASE_URL)
        self.assertEqual(results, [{"name": "Mock Product"}])


if __name__ == "__main__":
    unittest.main()
