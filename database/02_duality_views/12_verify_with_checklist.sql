-- =====================================================================
-- D2 / Step 4 verification (read-only): both arrays and the unit must agree with the tables
-- Run as : quality_app, after 11_inspection_card_dv_with_checklist.sql
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'Y1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)    AS table_rows;
-- Expected: 2 and 2

SELECT 'Y2 documents' AS check_name;
SELECT JSON_PRETTY(data) AS doc
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: card 1 checklist has three YES elements with answered_by 1;
--           card 2 checklist has three PENDING elements with null answered_by and answered_at.

SELECT 'Y3 relational rows for comparison' AS check_name;
SELECT card_id, checklist_result_id, checklist_definition_id, answer_code, answered_by
FROM checklist_result
ORDER BY card_id, checklist_result_id;
-- Expected: 6 rows (3 per card)

SELECT 'Y4 array type and length per card, both arrays' AS check_name;
SELECT data->>'$._id' AS card_id,
       JSON_TYPE(data->'$.measurements') AS measurements_type, JSON_LENGTH(data->'$.measurements') AS measurements_length,
       JSON_TYPE(data->'$.checklist')    AS checklist_type,    JSON_LENGTH(data->'$.checklist')    AS checklist_length
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: ARRAY, 2, ARRAY, 3 for both cards

SELECT 'Y5a total checklist elements versus table rows' AS check_name;
SELECT (SELECT COUNT(*) FROM checklist_result) AS table_rows,
       (SELECT SUM(JSON_LENGTH(data->'$.checklist')) FROM inspection_card_dv) AS elements_in_documents;
-- Expected: 6 and 6

SELECT 'Y5b checklist element-by-element agreement' AS check_name;
SELECT COUNT(*) AS elements_compared,
       SUM( (cr.card_id = CAST(d.data->>'$._id' AS UNSIGNED))
        AND (cr.checklist_definition_id = jt.checklist_definition_id)
        AND (cr.answer_code = jt.answer_code)
        AND (cr.answered_by <=> jt.answered_by) ) AS elements_fully_matching
FROM inspection_card_dv d,
     JSON_TABLE(d.data, '$.checklist[*]' COLUMNS (
         checklist_result_id     INT         PATH '$.checklist_result_id',
         checklist_definition_id INT         PATH '$.checklist_definition_id',
         answer_code             VARCHAR(20) PATH '$.answer_code',
         answered_by             INT         PATH '$.answered_by')) AS jt,
     checklist_result cr
WHERE cr.checklist_result_id = jt.checklist_result_id;
-- Expected: 6 and 6

SELECT 'Y5c measurements array still agrees (re-check of step 3)' AS check_name;
SELECT COUNT(*) AS elements_compared,
       SUM( (mr.card_id = CAST(d.data->>'$._id' AS UNSIGNED))
        AND (mr.result_status = jt.result_status)
        AND (mr.measured_value <=> jt.measured_value) ) AS elements_fully_matching
FROM inspection_card_dv d,
     JSON_TABLE(d.data, '$.measurements[*]' COLUMNS (
         measurement_result_id INT           PATH '$.measurement_result_id',
         result_status         VARCHAR(20)   PATH '$.result_status',
         measured_value        DECIMAL(10,3) PATH '$.measured_value')) AS jt,
     measurement_result mr
WHERE mr.measurement_result_id = jt.measurement_result_id;
-- Expected: 4 and 4

SELECT 'Y6 checklist array order as returned (observation)' AS check_name;
SELECT data->>'$._id' AS card_id,
       JSON_EXTRACT(data, '$.checklist[*].checklist_result_id') AS ids_in_document_order
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'Y7 the nested unit is still present and correct' AS check_name;
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.unit.unit_serial' = u.unit_serial)
        AND (CAST(d.data->>'$.unit.unit_id' AS UNSIGNED) = c.unit_id) ) AS cards_unit_matching
FROM inspection_card c
JOIN production_unit u ON u.unit_id = c.unit_id
JOIN inspection_card_dv d ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
-- Expected: 2 and 2

SELECT 'Y8 open_unit_key must not be exposed' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_dv
WHERE JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0

SELECT 'Y9 etag of each card in this view version (record for the ETag-by-version table)' AS check_name;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS etag
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
