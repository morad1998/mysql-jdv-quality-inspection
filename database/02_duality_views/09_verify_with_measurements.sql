-- =====================================================================
-- D2 / Step 3 verification (read-only): the nested array must agree with the tables
-- Run as : quality_app, after 08_inspection_card_dv_with_measurements.sql
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'X1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)    AS table_rows;
-- Expected: 2 and 2

SELECT 'X2 documents' AS check_name;
SELECT JSON_PRETTY(data) AS doc
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: card 1 has a RECORDED element (1000.250) and a NOT_APPLICABLE element;
--           card 2 has two PENDING elements with null values.
--           Record how the decimal value is written (1000.250 or 1000.25).

SELECT 'X3 relational rows for comparison' AS check_name;
SELECT card_id, measurement_result_id, measurement_definition_id, result_status, measured_value, recorded_by
FROM measurement_result
ORDER BY card_id, measurement_result_id;
-- Expected: 4 rows (2 per card)

SELECT 'X4 array type and length per card' AS check_name;
SELECT data->>'$._id' AS card_id,
       JSON_TYPE(data->'$.measurements') AS array_type,
       JSON_LENGTH(data->'$.measurements') AS array_length
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: ARRAY and 2 for both cards

SELECT 'X5a total elements versus table rows' AS check_name;
SELECT (SELECT COUNT(*) FROM measurement_result) AS table_rows,
       (SELECT SUM(JSON_LENGTH(data->'$.measurements')) FROM inspection_card_dv) AS elements_in_documents;
-- Expected: 4 and 4

SELECT 'X5b element-by-element agreement, matched by measurement_result_id' AS check_name;
SELECT COUNT(*) AS elements_compared,
       SUM( (mr.card_id = CAST(d.data->>'$._id' AS UNSIGNED))
        AND (mr.measurement_definition_id = jt.measurement_definition_id)
        AND (mr.result_status = jt.result_status)
        AND (mr.measured_value <=> jt.measured_value)
        AND (mr.recorded_by <=> jt.recorded_by) ) AS elements_fully_matching
FROM inspection_card_dv d,
     JSON_TABLE(d.data, '$.measurements[*]' COLUMNS (
         measurement_result_id     INT           PATH '$.measurement_result_id',
         measurement_definition_id INT           PATH '$.measurement_definition_id',
         result_status             VARCHAR(20)   PATH '$.result_status',
         measured_value            DECIMAL(10,3) PATH '$.measured_value',
         recorded_by               INT           PATH '$.recorded_by')) AS jt,
     measurement_result mr
WHERE mr.measurement_result_id = jt.measurement_result_id;
-- Expected: 4 and 4. If this shows a mismatch, check the JSON null handling of the
-- JSON_TABLE columns before blaming the view.

SELECT 'X6 array order as MySQL returns it (observation, not pass or fail)' AS check_name;
SELECT data->>'$._id' AS card_id,
       JSON_EXTRACT(data, '$.measurements[*].measurement_result_id') AS ids_in_document_order
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'X7 the nested unit is still present and correct' AS check_name;
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.unit.unit_serial' = u.unit_serial)
        AND (CAST(d.data->>'$.unit.unit_id' AS UNSIGNED) = c.unit_id) ) AS cards_unit_matching
FROM inspection_card c
JOIN production_unit u ON u.unit_id = c.unit_id
JOIN inspection_card_dv d ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
-- Expected: 2 and 2

SELECT 'X8 open_unit_key must not be exposed' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_dv
WHERE JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0
