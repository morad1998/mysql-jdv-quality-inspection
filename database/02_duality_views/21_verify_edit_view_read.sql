-- =====================================================================
-- D2 / Step 7a verification (read-only): the edit view reads correctly, and the read view is untouched
-- Run as : quality_app, after 20_inspection_card_edit_dv.sql
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'V1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_edit_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)         AS table_rows;
-- Expected: 2 and 2

SELECT 'V2 documents' AS check_name;
SELECT JSON_PRETTY(data) AS doc
FROM inspection_card_edit_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: only _id, _metadata, card_status, disposition, closed_by, closed_at; no unit, no opened_by

SELECT 'V3 keys of each document' AS check_name;
SELECT data->>'$._id' AS card_id, JSON_KEYS(data) AS keys_in_stored_order
FROM inspection_card_edit_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'V4 field-by-field agreement with the table' AS check_name;
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.card_status' = c.card_status)
        AND (NULLIF(d.data->>'$.disposition','null') <=> c.disposition)
        AND (CAST(NULLIF(d.data->>'$.closed_by','null') AS UNSIGNED) <=> c.closed_by)
        AND ((NULLIF(d.data->>'$.closed_at','null') IS NOT NULL) = (c.closed_at IS NOT NULL)) ) AS cards_fully_matching
FROM inspection_card c
JOIN inspection_card_edit_dv d ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
-- Expected: 2 and 2

SELECT 'V5 open_unit_key must not be exposed' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_edit_dv
WHERE JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0

SELECT 'V6 etag of each card in the edit view (a different shape, so different from the read view)' AS check_name;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS edit_view_etag
FROM inspection_card_edit_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'V7 regression: the read view is still valid and its etags are unchanged (step 6 values)' AS check_name;
SELECT TABLE_NAME, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME = 'inspection_card_dv';
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS read_view_etag
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: valid, READ_ONLY 1; etags 3771df754a7104188f3b9139d41986a7 and a1d3e9312e549f7dad4fb6c001b2532c
