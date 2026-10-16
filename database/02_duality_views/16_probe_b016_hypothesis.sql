-- =====================================================================
-- D2 / Step 5: test the B-016 hypothesis with two THROWAWAY views
-- Run as : quality_app, with the mysql client option --force
-- The real view inspection_card_dv is NOT touched. The two probe views are created here and
-- dropped at the end of the script. Every update runs in a transaction that is rolled back.
--
-- Question: a real change inside an array element is refused with ERROR 6497, but the error
--           names `inspection_card`.unit_id, path $.unit.unit_id. Is that the JOIN column of the
--           nested unit object, or just the FIRST field of the first nested object?
--
--   probe_a_dv : card fields + measurements array, NO nested unit.
--   probe_b_dv : card fields + nested unit with unit_serial BEFORE unit_id + measurements array.
--
-- Reading the result:
--   probe_b array error names unit_id     -> consistent with "join column of the nested object"
--   probe_b array error names unit_serial -> consistent with "first field of the first nested object"
--   probe_a array error names something other than unit -> the unit object matters
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS probe_a_dv;
DROP VIEW IF EXISTS probe_b_dv;

CREATE JSON RELATIONAL DUALITY VIEW probe_a_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id,
    'opened_by': opened_by,
    'measurements': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'measurement_result_id': measurement_result_id,
                'result_status': result_status
            )
        )
        FROM measurement_result
        WHERE measurement_result.card_id = inspection_card.card_id
    )
)
FROM inspection_card;

CREATE JSON RELATIONAL DUALITY VIEW probe_b_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id,
    'opened_by': opened_by,
    'unit': (
        SELECT JSON_DUALITY_OBJECT(
            'unit_serial': unit_serial,
            'unit_id': unit_id
        )
        FROM production_unit
        WHERE production_unit.unit_id = inspection_card.unit_id
    ),
    'measurements': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'measurement_result_id': measurement_result_id,
                'result_status': result_status
            )
        )
        FROM measurement_result
        WHERE measurement_result.card_id = inspection_card.card_id
    )
)
FROM inspection_card;

SELECT 'probe views created' AS test_step;
SELECT TABLE_NAME, ROOT_TABLE_NAME, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME LIKE 'probe\_%'
ORDER BY TABLE_NAME;
-- Expected: probe_a_dv and probe_b_dv, inspection_card, 1, valid

SELECT 'A1 probe_a root field opened_by' AS test_step;
START TRANSACTION;
UPDATE probe_a_dv SET data = JSON_SET(data, '$.opened_by', 2) WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'A2 probe_a array element result_status' AS test_step;
START TRANSACTION;
UPDATE probe_a_dv SET data = JSON_SET(data, '$.measurements[0].result_status', 'CHANGED_THROUGH_VIEW') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'B1 probe_b root field opened_by' AS test_step;
START TRANSACTION;
UPDATE probe_b_dv SET data = JSON_SET(data, '$.opened_by', 2) WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'B2 probe_b nested object field unit_serial' AS test_step;
START TRANSACTION;
UPDATE probe_b_dv SET data = JSON_SET(data, '$.unit.unit_serial', 'SN-DEMO-CHANGED') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'B3 probe_b array element result_status' AS test_step;
START TRANSACTION;
UPDATE probe_b_dv SET data = JSON_SET(data, '$.measurements[0].result_status', 'CHANGED_THROUGH_VIEW') WHERE data->>'$._id' = '1';
ROLLBACK;

DROP VIEW IF EXISTS probe_a_dv;
DROP VIEW IF EXISTS probe_b_dv;

SELECT 'FINAL: probe views gone, data at baseline. EXPECT 0 probe views, opened_by 1 and 2, 4 measurement rows' AS test_step;
SELECT COUNT(*) AS probe_views_left
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME LIKE 'probe\_%';
SELECT card_id, opened_by FROM inspection_card ORDER BY card_id;
SELECT (SELECT COUNT(*) FROM measurement_result) AS measurement_rows,
       (SELECT result_status FROM measurement_result WHERE measurement_result_id = 1) AS result1_status;
