#!/usr/bin/env python3
"""
Rfam SQL Query Runner
=====================
Executes the three verified queries from answers.sql against the public
Rfam MySQL database and displays formatted results.

Connection Details:
    Host: mysql-rfam-public.ebi.ac.uk
    Port: 4497
    Database: Rfam
    User: rfamro
    Password: (none)
"""

import sys
import time
import pymysql

# Rfam public connection configuration
DB_CONFIG = {
    "host": "mysql-rfam-public.ebi.ac.uk",
    "port": 4497,
    "user": "rfamro",
    "passwd": "",
    "db": "Rfam",
    "connect_timeout": 30,
    "cursorclass": pymysql.cursors.DictCursor,
}

# The three verified SQL queries from answers.sql
QUERIES = [
    {
        "id": "2.1",
        "title": "Count of Acacia Species in Taxonomy",
        "sql": """
SELECT COUNT(DISTINCT tx.species) AS acacia_species_count
FROM taxonomy AS tx
WHERE tx.species LIKE 'Acacia%'
  AND tx.tax_string LIKE '%Viridiplantae%';
        """.strip(),
    },
    {
        "id": "2.2",
        "title": "Wheat with Longest DNA Sequence",
        "sql": """
SELECT
    tx.species,
    rs.rfamseq_acc,
    rs.length AS sequence_length
FROM rfamseq AS rs
JOIN taxonomy AS tx
    ON tx.ncbi_id = rs.ncbi_id
WHERE tx.species LIKE 'Triticum%'
ORDER BY rs.length DESC, tx.species ASC, rs.rfamseq_acc ASC
LIMIT 1;
        """.strip(),
    },
    {
        "id": "2.3",
        "title": "Paginated Families (Page 9, 15/page, Max Sequence > 1,000,000)",
        "sql": """
SELECT
    f.rfam_acc AS family_accession,
    f.rfam_id AS family_name,
    MAX(rs.length) AS max_sequence_length
FROM family AS f
JOIN full_region AS fr
    ON fr.rfam_acc = f.rfam_acc
JOIN rfamseq AS rs
    ON rs.rfamseq_acc = fr.rfamseq_acc
GROUP BY f.rfam_acc, f.rfam_id
HAVING MAX(rs.length) > 1000000
ORDER BY max_sequence_length DESC, f.rfam_acc ASC
LIMIT 15 OFFSET 120;
        """.strip(),
    },
]


def run_query(cursor, query_info):
    qid = query_info["id"]
    title = query_info["title"]
    sql = query_info["sql"]

    print(f"\n{'='*75}")
    print(f"Executing Question {qid}: {title}")
    print(f"{'='*75}")
    print(sql)
    print(f"{'-'*75}")

    start_time = time.time()
    cursor.execute(sql)
    rows = cursor.fetchall()
    duration = time.time() - start_time

    print(f"Returned {len(rows)} row(s) in {duration:.2f} seconds:\n")

    if not rows:
        print("  (No rows returned)")
        return

    # Print formatted table
    headers = list(rows[0].keys())
    col_widths = {h: max(len(h), max(len(str(r[h])) for r in rows)) for h in headers}

    header_line = " | ".join(h.ljust(col_widths[h]) for h in headers)
    separator = "-+-".join("-" * col_widths[h] for h in headers)
    print(header_line)
    print(separator)

    for r in rows:
        row_line = " | ".join(str(r[h]).ljust(col_widths[h]) for h in headers)
        print(row_line)


def main():
    print("Connecting to Rfam public MySQL database...")
    print(f"Host: {DB_CONFIG['host']}:{DB_CONFIG['port']} | DB: {DB_CONFIG['db']} | User: {DB_CONFIG['user']}")

    try:
        conn = pymysql.connect(**DB_CONFIG)
        print("Connection established successfully.")
    except Exception as exc:
        sys.stderr.write(f"Connection failed: {exc}\n")
        sys.exit(1)

    try:
        with conn.cursor() as cursor:
            for q in QUERIES:
                run_query(cursor, q)
    finally:
        conn.close()
        print("\nDatabase connection closed.")


if __name__ == "__main__":
    main()
