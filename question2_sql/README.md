# Question 2: Rfam SQL Queries & Database Analysis

Verified SQL solutions for the public [Rfam database](https://docs.rfam.org/en/latest/database.html) (relational schema covering RNA families, sequences, regions, and taxonomy).

---

## 1. Connection & Environment Details

The queries are executed directly against the official public read-only MySQL server hosted by EMBL-EBI:

- **Host:** `mysql-rfam-public.ebi.ac.uk`
- **Port:** `4497`
- **Database:** `Rfam`
- **User:** `rfamro`
- **Password:** *(none / empty string)*
- **Engine / Version:** MySQL 8.0.32-24

### Verified Table Schemas & Join Keys

Before formulating the queries, `DESCRIBE` was executed against all relevant tables on the live database:

1. **`taxonomy`** (Taxonomic lineage & species classification)
   - `ncbi_id` (`int unsigned`, PRIMARY KEY): NCBI taxonomy identifier.
   - `species` (`varchar(100)`, indexed): Scientific binomial species name.
   - `tax_string` (`mediumtext`): Full taxonomic lineage string (e.g. `Eukaryota; Viridiplantae; Streptophyta; ...`).
2. **`rfamseq`** (Source physical sequence records)
   - `rfamseq_acc` (`varchar(25)`, PRIMARY KEY): Unique sequence accession identifier.
   - `ncbi_id` (`int unsigned`, indexed): Join key linking sequence to `taxonomy.ncbi_id`.
   - `length` (`int unsigned`): Physical sequence length in base pairs.
   - `mol_type` (`enum`): Molecular type (e.g. `genomic DNA`, `RNA`).
   - `description` (`varchar(250)`): Sequence header / description.
3. **`full_region`** (Annotated regions linking families to sequences)
   - `rfam_acc` (`varchar(7)`, indexed): Join key linking to `family.rfam_acc`.
   - `rfamseq_acc` (`varchar(25)`, indexed): Join key linking to `rfamseq.rfamseq_acc`.
   - `is_significant` (`tinyint unsigned`): Region significance flag.
4. **`family`** (RNA family curation records)
   - `rfam_acc` (`varchar(7)`, PRIMARY KEY): Family accession (e.g. `RF00001`).
   - `rfam_id` (`varchar(40)`, indexed): Human-readable family identifier / name.

---

## 2. Query Analysis & Theoretical Justifications

### Question 2.1: Count of Acacia Plants in Taxonomy

```sql
SELECT COUNT(DISTINCT tx.species) AS acacia_species_count
FROM taxonomy AS tx
WHERE tx.species LIKE 'Acacia%'
  AND tx.tax_string LIKE '%Viridiplantae%';
```

#### Why This Is Formulated This Way
- **Scientific Nomenclature:** *Acacia* is a genus of flowering plants in the family Fabaceae. In binomial nomenclature, every species in this genus has a scientific name starting with `Acacia ` (e.g., *Acacia acradenia*, *Acacia aneura*).
- **Lineage Verification:** Filtering on `tx.tax_string LIKE '%Viridiplantae%'` restricts results strictly to the green plant kingdom.
- **The Loose Matching Trap:** Searching loosely with `species LIKE '%Acacia%'` matches **63 completely unrelated non-plant organisms**, including:
  - Fungi: *Fusarium acaciae-mearnsii*, *Cercospora acaciae-mangii*
  - Insects: *Kladothrips acaciae* (thrips), *Caryedon acaciae* (seed beetle)
  - Damselflies: *Pseudagrion acaciae*
  - Rodents: *Thallomys paedulcus* (Acacia rat)
  - Other plant genera: *Arracacia* (e.g. *Arracacia xanthorrhiza*)
- **Counting Semantics:** In the live database, every row where `species LIKE 'Acacia%'` has a distinct `species` label and a distinct `ncbi_id`. Thus, `COUNT(DISTINCT tx.species)` and `COUNT(*)` both evaluate to **326**. All 326 rows belong to `Viridiplantae`.

**Verified Result:** **326**

---

### Question 2.2: Wheat with the Longest DNA Sequence

```sql
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
```

#### Why This Is Formulated This Way
- **Taxonomic Grounding:** True cultivated wheat belongs to the genus *Triticum* (such as *Triticum durum* and *Triticum aestivum*).
- **Common-Name Hazard:** Searching for `%wheat%` matches **58 entries** in `taxonomy`, including non-wheat organisms:
  - *Fagopyrum esculentum* (common buckwheat - not wheat, belongs to Polygonaceae)
  - Viruses: *Wheat dwarf virus*, *Wheat streak mosaic virus*
  - Fungi: *Tilletia caries* (wheat bunt fungus)
  - Pests: *Diuraphis noxia* (Russian wheat aphid), *Cephus cinctus* (wheat stem sawfly)
  - Birds: *Oenanthe deserti* (desert wheatear)
- **Deterministic Ordering:** Sorting by `rs.length DESC` with deterministic tie-breakers (`tx.species ASC`, `rs.rfamseq_acc ASC`) ensures reproducibility even if multiple accessions share the same length.
- **Molecular Type (`mol_type`) Verification:** Schema inspection shows `rfamseq.mol_type` is an `enum` column. The top accession `LT934116.1` was verified on the live database to have `mol_type = 'genomic DNA'`. Comparing the query with an explicit DNA filter (`AND rs.mol_type LIKE '%DNA%'`) produces identical results (*Triticum durum*, accession `LT934116.1`); neither the returned species nor accession change.

**Verified Result:**
- **Species:** `Triticum durum (durum wheat)`
- **Accession:** `LT934116.1`
- **Sequence Length:** `836,514,780` bp (Chromosome 5B assembly)
- **Molecular Type:** `genomic DNA`
*(Runner-up: `Triticum aestivum (bread wheat)`, accession `LS992087.1`, length `830,829,764` bp, also `genomic DNA`).*

---

### Question 2.3 & 2.4: Paginated List of Families by Longest Sequence Length

```sql
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
```

#### Why This Is Formulated This Way
- **Relational Path:** `family` links to `full_region` on `rfam_acc`; `full_region` links to `rfamseq` on `rfamseq_acc`.
- **Aggregation:** We group by `f.rfam_acc, f.rfam_id` and compute `MAX(rs.length)` to find the longest sequence annotated for that family.
- **HAVING Clause:** The requirement is to filter families whose *maximum sequence length* exceeds 1,000,000. Because this applies to the aggregated group maximum, it belongs in `HAVING MAX(rs.length) > 1000000`.
- **Pagination Arithmetic:**
  $$\text{OFFSET} = (\text{Page} - 1) \times \text{PageSize} = (9 - 1) \times 15 = 120$$
  Clause: `LIMIT 15 OFFSET 120`.
- **Deterministic Tie-Breaking:** `f.rfam_acc ASC` ensures rows with equal maximum lengths do not shift arbitrarily across page boundaries. In the live database, many RNA families are annotated on the massive 836,514,780 bp wheat genome assembly sequence; therefore, deterministic sorting by accession tie-breaker is essential.

**Verified Live Results (Page 9, Rows 121–135):**

| Row # | Family Accession (`rfam_acc`) | Family Name (`rfam_id`) | Maximum Sequence Length (`max_sequence_length`) |
| :---: | :--- | :--- | :---: |
| **121** | `RF01219` | `snoR100` | 836,514,780 |
| **122** | `RF01220` | `snoR104` | 836,514,780 |
| **123** | `RF01224` | `snoR80` | 836,514,780 |
| **124** | `RF01227` | `snoR83` | 836,514,780 |
| **125** | `RF01284` | `snoR8a` | 836,514,780 |
| **126** | `RF01286` | `snoR26` | 836,514,780 |
| **127** | `RF01292` | `snoR2` | 836,514,780 |
| **128** | `RF01300` | `snoU49` | 836,514,780 |
| **129** | `RF01847` | `Plant_U3` | 836,514,780 |
| **130** | `RF01848` | `ACEA_U3` | 836,514,780 |
| **131** | `RF01856` | `Protozoa_SRP` | 836,514,780 |
| **132** | `RF01911` | `MIR2118` | 836,514,780 |
| **133** | `RF03160` | `twister-P1` | 836,514,780 |
| **134** | `RF03209` | `MIR9657` | 836,514,780 |
| **135** | `RF03674` | `MIR5387` | 836,514,780 |

*Execution time on public server: ~592 seconds (scanning across 10,310,293 region rows and 81,044,540 sequences).*
*Optimization note: An alternative formulation with `WHERE rs.length > 1000000` was empirically benchmarked on the live database, executing in 626.43 seconds and yielding the exact same 15 rows. Because `rfamseq.length` is unindexed, MySQL still performs ~2.3 million primary key lookups into `rfamseq`, confirming that pre-filtering provides no runtime benefit.*

---

## 3. How to Run the Queries

### Option A: Via Python Runner (cross-platform, recommended)

```bash
# Install dependency
pip install -r question2_sql/requirements.txt

# Run query by query individually:
python question2_sql/run_queries.py 2.1   # Fast (~0.3s): Acacia species count
python question2_sql/run_queries.py 2.2   # Fast (~6s): Longest wheat DNA sequence
python question2_sql/run_queries.py 2.3   # Long (~10 min): Paginated RNA families

# Or run all three sequentially:
python question2_sql/run_queries.py
```

### Option B: Via Native MySQL CLI

```bash
mysql -h mysql-rfam-public.ebi.ac.uk -P 4497 -u rfamro Rfam < question2_sql/answers.sql
```

### Option C: Via Bash Wrapper (Linux / macOS)

```bash
chmod +x question2_sql/run_queries.sh
./question2_sql/run_queries.sh
```

---

## 4. Verification & Interview Defense Summary

1. **Why `Viridiplantae` in Query 2.1?**
   Because *Acacia* is a genus of green plants. An unconstrained match on `%Acacia%` matches 63 non-plant records including insects, fungi, damselflies, rodents, and other plant genera like *Arracacia*. All 326 rows starting with `Acacia%` belong to *Viridiplantae*.
2. **Why `Triticum%` in Query 2.2?**
   Cultivated wheat belongs to the botanical genus *Triticum*. Matching `%wheat%` captures unrelated organisms like buckwheat (which is not wheat), wheat dwarf virus, wheat bunt fungus, and wheatear birds. The query returns *Triticum durum* with accession `LT934116.1` and length `836,514,780` bp.
3. **Why `HAVING` and not `WHERE` in Query 2.3?**
   The requirement is that each family's *maximum* sequence length exceeds 1,000,000. Aggregations (`MAX`) cannot be evaluated in a `WHERE` clause before grouping; they belong in `HAVING MAX(rs.length) > 1000000`.
4. **Why `OFFSET 120`?**
   Page 9 with 15 records per page requires skipping $(9 - 1) \times 15 = 120$ rows (`LIMIT 15 OFFSET 120`).
