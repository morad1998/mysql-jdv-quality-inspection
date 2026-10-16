-- =====================================================================
-- D2 / Step 7b verification (read-only): the edit view arrays read correctly
-- Run as : quality_app, after 23_inspection_card_edit_dv_with_arrays.sql
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'U1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_edit_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)         AS table_rows;
-- Expected: 2 and 2

SELECT 'U2 documents' AS check_name;
SELECT JSON_PRETTY(data) AS doc
FROM inspection_card_edit_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: root fields, a measurements array of 2 and a checklist array of 3 per card

SELECT 'U3 keys of one element of each array, card 1 (no definition ids expected)' AS check_name;
SELECT JSON_KEYS(data->'$.measurements[0]') AS measurement_keys,
       JSON_KEYS(data->'$.checklist[0]')    AS checklist_keys
FROM inspection_card_edit_dv WHERE data->>'$._id' = '1';

SELECT 'U4 array lengths and element agreement with the tables' AS check_name;
SELECT (SELECT SUM(JSON_LENGTH(data->'$.measurements')) FROM inspection_card_edit_dv) AS measurement_elements,
       (SELECT COUNT(*) FROM measurement_result) AS measurement_rows,
       (SELECT SUM(JSON_LENGTH(data->'$.checklist')) FROM inspection_card_edit_dv) AS checklist_elements,
       (SELECT COUNT(*) FROM checklist_result) AS checklist_rows;
-- Expected: 4, 4, 6, 6

SELECT COUNT(*) AS measurement_elements_compared,
       SUM( (mr.card_id = CAST(d.data->>'$._id' AS UNSIGNED))
        AND (mr.result_status = jt.result_status)
        AND (mr.measured_value <=> jt.measured_value)
        AND (mr.recorded_by <=> jt.recorded_by) ) AS measurement_elements_matching
FROM inspection_card_edit_dv d,
     JSON_TABLE(d.data, '$.measurements[*]' COLUMNS (
         measurement_result_id INT           PATH '$.measurement_result_id',
         result_status         VARCHAR(20)   PATH '$.result_status',
         measured_value        DECIMAL(10,3) PATH '$.measured_value',
         recorded_by           INT           PATH '$.recorded_by')) AS jt,
     measurement_result mr
WHERE mr.measurement_result_id = jt.measurement_result_id;
-- Expected: 4 and 4

SELECT COUNT(*) AS checklist_elements_compared,
       SUM( (cr.card_id = CAST(d.data->>'$._id' AS UNSIGNED))
        AND (cr.answer_code = jt.answer_code)
        AND (cr.answered_by <=> jt.answered_by) ) AS checklist_elements_matching
FROM inspection_card_edit_dv d,
     JSON_TABLE(d.data, '$.checklist[*]' COLUMNS (
         checklist_result_id INT         PATH '$.checklist_result_id',
         answer_code         VARCHAR(20) PATH '$.answer_code',
         answered_by         INT         PATH '$.answered_by')) AS jt,
     checklist_result cr
WHERE cr.checklist_result_id = jt.checklist_result_id;
-- Expected: 6 and 6

SELECT 'U5 open_unit_key must not be exposed' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_edit_dv
WHERE JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0

SELECT 'U6 etag of each card in this edit-view version (record for the ETag table)' AS check_name;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS edit_view_etag
FROM inspection_card_edit_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: different from the root-only edit view (9052eccb... and b59ab53f...)

SELECT 'U7 regression: the read view is still valid and its etags are unchanged' AS check_name;
SELECT TABLE_NAME, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME = 'inspection_card_dv';
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS read_view_etag
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: valid, READ_ONLY 1; etags 3771df754a7104188f3b9139d41986a7 and a1d3e9312e549f7dad4fb6c001b2532c
