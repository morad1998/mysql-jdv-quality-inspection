-- =====================================================================
-- D2 / Step 2 verification (read-only): the nested JSON must agree with the tables
-- Run as : quality_app, after 05_inspection_card_dv_with_unit.sql
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'W1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)    AS table_rows;
-- Expected: 2 and 2

SELECT 'W2 documents' AS check_name;
SELECT JSON_PRETTY(data) AS doc
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: each document has a nested "unit" object with unit_id, unit_serial, work_order_id

SELECT 'W3 relational rows for comparison' AS check_name;
SELECT c.card_id, c.unit_id, u.unit_serial, u.work_order_id, c.card_status, c.disposition
FROM inspection_card c
JOIN production_unit u ON u.unit_id = c.unit_id
ORDER BY c.card_id;
-- Expected: card 1 and card 2, both on unit 1 (SN-DEMO-0001) in work order 1

SELECT 'W4 nested object type' AS check_name;
SELECT data->>'$._id' AS card_id, JSON_TYPE(data->'$.unit') AS unit_node_type
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: OBJECT for both

SELECT 'W5 field-by-field agreement including the nested object' AS check_name;
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.card_status' = c.card_status)
        AND (NULLIF(d.data->>'$.disposition','null') <=> c.disposition)
        AND (CAST(d.data->>'$.opened_by' AS UNSIGNED) = c.opened_by)
        AND (CAST(NULLIF(d.data->>'$.closed_by','null') AS UNSIGNED) <=> c.closed_by)
        AND (CAST(d.data->>'$.unit.unit_id' AS UNSIGNED) = c.unit_id)
        AND (d.data->>'$.unit.unit_serial' = u.unit_serial)
        AND (CAST(d.data->>'$.unit.work_order_id' AS UNSIGNED) = u.work_order_id) ) AS cards_fully_matching
FROM inspection_card c
JOIN production_unit u ON u.unit_id = c.unit_id
JOIN inspection_card_dv d ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
-- Expected: 2 and 2

SELECT 'W6 open_unit_key must not be exposed anywhere in the document' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_dv
WHERE JSON_SEARCH(data, 'all', 'open_unit_key') IS NOT NULL
   OR JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0 (note: JSON_SEARCH looks at values, so this is a coarse second check only)
