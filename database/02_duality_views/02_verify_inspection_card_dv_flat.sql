-- =====================================================================
-- D2 / Step 1 verification (read-only): the JSON must agree with the relational rows
-- Run as : quality_app, after 01_inspection_card_dv_flat.sql
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'V1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)    AS table_rows;
-- Expected: 2 and 2 (cards 1 and 2 from the D1 tests)

SELECT 'V2 documents' AS check_name;
SELECT JSON_PRETTY(data) AS doc
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: card 1 CLOSED / PASS and card 2 REJECTED / REJECT, each with _metadata.etag

SELECT 'V3 relational rows for comparison' AS check_name;
SELECT card_id, unit_id, card_status, disposition, opened_by, closed_by
FROM inspection_card
ORDER BY card_id;

SELECT 'V4 field-by-field agreement' AS check_name;
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.card_status' = c.card_status)
        AND (NULLIF(d.data->>'$.disposition','null') <=> c.disposition)
        AND (CAST(d.data->>'$.unit_id' AS UNSIGNED) = c.unit_id)
        AND (CAST(d.data->>'$.opened_by' AS UNSIGNED) = c.opened_by)
        AND (CAST(NULLIF(d.data->>'$.closed_by','null') AS UNSIGNED) <=> c.closed_by) ) AS cards_fully_matching
FROM inspection_card c
JOIN inspection_card_dv d
  ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
-- Expected: 2 and 2. Dates are not asserted here; read them side by side in V2 and V3 and
-- record how MySQL formats DATETIME inside a document.

SELECT 'V5 open_unit_key must not be exposed' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_dv
WHERE JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0
