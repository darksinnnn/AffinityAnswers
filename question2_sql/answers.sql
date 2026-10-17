-- ==============================================================================
-- Affinity Answers — Question 2: Rfam SQL Queries
-- Database: Rfam (Public Read-Only MySQL Endpoint)
-- Host: mysql-rfam-public.ebi.ac.uk | Port: 4497 | User: rfamro | DB: Rfam
-- ==============================================================================


-- ==============================================================================
-- Question 2.1: How many types of Acacia plants can be found in the taxonomy table?
-- ==============================================================================
-- Taxonomic & Biological Justification:
-- 1. Genus Acacia: In standard botanical nomenclature, plant species belong to the
--    genus 'Acacia'. In the taxonomy table, their binomial species names begin with
--    'Acacia ' (e.g. 'Acacia acradenia', 'Acacia aneura', etc.).
-- 2. Lineage Verification: All species starting with 'Acacia%' in Rfam's taxonomy
--    table belong to the green plants lineage:
--    'Eukaryota; Viridiplantae; Streptophyta; Embryophyta; Tracheophyta; ...'.
-- 3. Loose Match Risk: Searching '%Acacia%' carelessly matches 63 completely unrelated
--    taxa, including insects (Kladothrips acaciae, Caryedon acaciae), fungi
--    (Fusarium acaciae-mearnsii), damselflies (Pseudagrion acaciae), rodents
--    (Thallomys paedulcus / Acacia rat), and separate plant genera (Arracacia).
-- 4. Counting Expression: Every row starting with 'Acacia%' represents a distinct
--    species label and distinct ncbi_id. Using COUNT(DISTINCT tx.species) ensures
--    we count distinct biological species types.
--
-- Verified Count: 326
-- ==============================================================================

SELECT COUNT(DISTINCT tx.species) AS acacia_species_count
FROM taxonomy AS tx
WHERE tx.species LIKE 'Acacia%'
  AND tx.tax_string LIKE '%Viridiplantae%';



-- ==============================================================================
-- Question 2.2: Which type of wheat has the longest DNA sequence?
-- Hint: Use the rfamseq and taxonomy tables.
-- ==============================================================================
-- Taxonomic & Structural Justification:
-- 1. Botanical Identity: True cultivated wheat belongs to the genus 'Triticum'
--    (e.g., Triticum aestivum [bread wheat], Triticum durum [durum wheat]).
-- 2. Common-Name Hazard: Searching `species LIKE '%wheat%'` matches 58 rows including
--    buckwheat (Fagopyrum esculentum, which is not wheat), wheat dwarf virus,
--    wheat bunt fungus (Tilletia caries), wheat aphid (Diuraphis noxia), and
--    wheatear birds (Oenanthe deserti).
-- 3. Schema Join: Joins `rfamseq` to `taxonomy` on `ncbi_id`.
-- 4. Deterministic Ordering: Orders descending by `rs.length`. Additional sort keys
--    (`tx.species ASC`, `rs.rfamseq_acc ASC`) resolve any potential ties.
--
-- Verified Result:
-- Species: Triticum durum (durum wheat)
-- Accession: LT934116.1
-- Sequence Length: 836,514,780 bp (Chromosome 5B assembly)
-- ==============================================================================

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



-- ==============================================================================
-- Question 2.3 & 2.4: Paginate a list of families and their longest DNA sequence lengths.
-- Requirements:
--   - Include only families whose longest DNA sequence is greater than 1,000,000.
--   - Sorted by maximum sequence length in descending order.
--   - Return family accession ID (rfam_acc), family name (rfam_id), and maximum sequence length.
--   - Return page 9 with 15 results per page.
-- ==============================================================================
-- Structural & Aggregation Justification:
-- 1. Relational Path:
--    `family` stores family metadata (`rfam_acc` PK, `rfam_id` family name).
--    `full_region` maps family accessions (`rfam_acc`) to sequence accessions (`rfamseq_acc`).
--    `rfamseq` stores sequence physical properties (`rfamseq_acc` PK, `length`).
-- 2. Aggregation: Groups by `f.rfam_acc, f.rfam_id` and calculates `MAX(rs.length)`.
-- 3. Threshold Filtering: The requirement specifies families whose *longest* sequence
--    exceeds 1,000,000. This threshold belongs in the `HAVING` clause
--    (`HAVING MAX(rs.length) > 1000000`) to evaluate the aggregated maximum per family.
-- 4. Pagination Arithmetic:
--    Page 9 with 15 rows per page: OFFSET = (Page - 1) * PageSize = (9 - 1) * 15 = 120.
--    Clause: `LIMIT 15 OFFSET 120`.
-- 5. Tie-Breaker: `f.rfam_acc ASC` ensures deterministic ordering when maximum lengths match.
-- 6. Performance & Execution Plan Note:
--    Joining `family` (4,018) -> `full_region` (10,310,293) -> `rfamseq` (81,044,540)
--    on a public WAN MySQL server performs ~2.3 million indexed primary key lookups into `rfamseq`,
--    running in ~592 seconds. An equivalent formulation that adds `WHERE rs.length > 1000000`
--    before grouping is logically valid because any family whose maximum sequence length exceeds
--    1,000,000 must contain at least one sequence meeting that condition.
-- ==============================================================================

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

