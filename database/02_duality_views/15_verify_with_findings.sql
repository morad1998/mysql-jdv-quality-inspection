-- =====================================================================
-- D2 / Step 5 verification: all three arrays and the unit must agree with the tables
-- Run as : quality_app, with the mysql client option --force
-- Parts Z1 to Z9 are read-only. Parts R1 to R3 change data inside transactions that are
-- rolled back and then check the baseline (R1 uses the next AUTO_INCREMENT id of quality_finding).
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'Z1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)    AS table_rows;
-- Expected: 2 and 2

SELECT 'Z2 findings part of each document' AS check_name;
SELECT data->>'$._id' AS card_id, JSON_PRETTY(data->'$.findings') AS findings
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: card 1 has one element (finding 1, CRITICAL, RESOLVED, with resolved_at set);
--           card 2 shows null (JSON null) because it has no findings.

SELECT 'Z3 relational rows for comparison' AS check_name;
SELECT finding_id, card_id, severity, finding_status, raised_by, (resolved_at IS NOT NULL) AS has_resolved_at
FROM quality_finding
ORDER BY finding_id;
-- Expected: 1 row (finding 1 on card 1)

SELECT 'Z4 type of each array node per card' AS check_name;
SELECT data->>'$._id' AS card_id,
       JSON_TYPE(data->'$.measurements') AS measurements_type,
       JSON_TYPE(data->'$.checklist')    AS checklist_type,
       JSON_TYPE(data->'$.findings')     AS findings_type
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: card 1 ARRAY, ARRAY, ARRAY; card 2 ARRAY, ARRAY and NULL for findings (the JSON null)

SELECT 'Z5a element counts versus table rows, counting real arrays only' AS check_name;
SELECT (SELECT COUNT(*) FROM measurement_result) AS measurement_rows,
       (SELECT COUNT(*) FROM checklist_result)   AS checklist_rows,
       (SELECT COUNT(*) FROM quality_finding)    AS finding_rows,
       SUM(CASE WHEN JSON_TYPE(data->'$.measurements') = 'ARRAY' THEN JSON_LENGTH(data->'$.measurements') ELSE 0 END) AS measurement_elements,
       SUM(CASE WHEN JSON_TYPE(data->'$.checklist')    = 'ARRAY' THEN JSON_LENGTH(data->'$.checklist')    ELSE 0 END) AS checklist_elements,
       SUM(CASE WHEN JSON_TYPE(data->'$.findings')     = 'ARRAY' THEN JSON_LENGTH(data->'$.findings')     ELSE 0 END) AS finding_elements
FROM inspection_card_dv;
-- Expected: 4, 6, 1 and 4, 6, 1

SELECT 'Z5b findings element-by-element agreement' AS check_name;
SELECT COUNT(*) AS elements_compared,
       SUM( (qf.card_id = CAST(d.data->>'$._id' AS UNSIGNED))
        AND (qf.severity = jt.severity)
        AND (qf.finding_status = jt.finding_status)
        AND (qf.description = jt.description)
        AND (qf.raised_by = jt.raised_by)
        AND (qf.resolved_at IS NOT NULL) = (jt.resolved_at IS NOT NULL) ) AS elements_fully_matching
FROM inspection_card_dv d,
     JSON_TABLE(d.data, '$.findings[*]' COLUMNS (
         finding_id     INT          PATH '$.finding_id',
         severity       VARCHAR(10)  PATH '$.severity',
         finding_status VARCHAR(10)  PATH '$.finding_status',
         description    VARCHAR(500) PATH '$.description',
         raised_by      INT          PATH '$.raised_by',
         resolved_at    VARCHAR(40)  PATH '$.resolved_at')) AS jt,
     quality_finding qf
WHERE JSON_TYPE(d.data->'$.findings') = 'ARRAY'
  AND qf.finding_id = jt.finding_id;
-- Expected: 1 and 1

SELECT 'Z6 findings array order as returned (observation; see R1 for more than one element)' AS check_name;
SELECT data->>'$._id' AS card_id, JSON_EXTRACT(data, '$.findings[*].finding_id') AS ids_in_document_order
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'Z7 the nested unit is still present and correct' AS check_name;
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.unit.unit_serial' = u.unit_serial)
        AND (CAST(d.data->>'$.unit.unit_id' AS UNSIGNED) = c.unit_id) ) AS cards_unit_matching
FROM inspection_card c
JOIN production_unit u ON u.unit_id = c.unit_id
JOIN inspection_card_dv d ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
-- Expected: 2 and 2

SELECT 'Z8 open_unit_key must not be exposed' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_dv
WHERE JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0

SELECT 'Z9 etag of each card in this view version' AS check_name;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS etag
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'R1 add a finding to card 1 by direct table insert (rolled back): EXPECT two elements and a changed etag' AS test_step;
START TRANSACTION;
INSERT INTO quality_finding (card_id, severity, description, raised_by)
VALUES (1, 'MINOR', 'Demo minor finding for rollback test', 1);
SELECT JSON_LENGTH(data->'$.findings') AS findings_length,
       JSON_EXTRACT(data, '$.findings[*].finding_id') AS ids_in_document_order,
       data->>'$._metadata.etag' AS card1_etag_with_extra_finding
FROM inspection_card_dv WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'R2 REAL change to a findings element through the read-only view -> EXPECT ERROR 6497 (record which path it names)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv
   SET data = JSON_SET(data, '$.findings[0].severity', 'MINOR')
 WHERE data->>'$._id' = '1';
SELECT severity FROM quality_finding WHERE finding_id = 1;
ROLLBACK;

SELECT 'R3 after the rollbacks. EXPECT 1 finding row, severity CRITICAL, and the etags from Z9' AS test_step;
SELECT (SELECT COUNT(*) FROM quality_finding) AS finding_rows,
       (SELECT severity FROM quality_finding WHERE finding_id = 1) AS finding1_severity;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS etag
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
