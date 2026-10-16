-- =====================================================================
-- D2 / Step 6: discriminating probe for B-016 (one throwaway view)
-- Run as : quality_app, with the mysql client option --force
-- The real view inspection_card_dv is NOT touched. probe_c_dv is created here and dropped at
-- the end. Every update runs in a transaction that is rolled back.
--
-- Why: probe_b_dv in step 5 wrote unit_serial before unit_id, but MySQL stores JSON keys
-- shorter-first, so unit_id stayed the first key. Here the nested object has the key 'sn'
-- (2 characters) for unit_serial and the key 'unit_id' (7 characters) for the join column,
-- so in stored order 'sn' comes FIRST and the join column comes second.
--
-- Reading the array-element error (C1):
--   names inspection_card.unit_id, path $.unit.unit_id    -> the JOIN COLUMN, not the first key
--   names production_unit.unit_serial, path $.unit.sn      -> the FIRST KEY of the nested object
--   anything else                                          -> record it; neither hypothesis fits
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS probe_c_dv;

CREATE JSON RELATIONAL DUALITY VIEW probe_c_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id,
    'opened_by': opened_by,
    'unit': (
        SELECT JSON_DUALITY_OBJECT(
            'sn': unit_serial,
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

SELECT 'probe_c_dv created; stored key order of the nested unit object (expect sn first)' AS test_step;
SELECT TABLE_NAME, ROOT_TABLE_NAME, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME = 'probe_c_dv';
SELECT JSON_KEYS(data->'$.unit') AS unit_keys_in_stored_order
FROM probe_c_dv WHERE data->>'$._id' = '1';

SELECT 'C1 array element result_status (decisive)' AS test_step;
START TRANSACTION;
UPDATE probe_c_dv SET data = JSON_SET(data, '$.measurements[0].result_status', 'CHANGED_THROUGH_VIEW') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'C2 nested object field sn (sanity: expect production_unit.unit_serial, $.unit.sn)' AS test_step;
START TRANSACTION;
UPDATE probe_c_dv SET data = JSON_SET(data, '$.unit.sn', 'SN-DEMO-CHANGED') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'C3 root field opened_by (sanity: expect inspection_card.opened_by, $.opened_by)' AS test_step;
START TRANSACTION;
UPDATE probe_c_dv SET data = JSON_SET(data, '$.opened_by', 2) WHERE data->>'$._id' = '1';
ROLLBACK;

DROP VIEW IF EXISTS probe_c_dv;

SELECT 'FINAL: probe view gone, data at baseline. EXPECT 0 probe views, opened_by 1 and 2, serial SN-DEMO-0001' AS test_step;
SELECT COUNT(*) AS probe_views_left
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME LIKE 'probe\_%';
SELECT card_id, opened_by FROM inspection_card ORDER BY card_id;
SELECT unit_serial FROM production_unit WHERE unit_id = 1;
