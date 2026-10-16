-- =====================================================================
-- D2 / Step 3: add the measurement results as the first nested ARRAY (still read-only)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Basis  : D1.9 plan: add one nested collection at a time, then compare with the tables.
-- Pattern: the array is a scalar subquery returning JSON_ARRAYAGG(JSON_DUALITY_OBJECT(...)),
--          the same pattern as customer_orders_dv in Day 0. No WITH clause, so read-only.
-- Scope  : array elements carry the measurement_result columns only. The definition
--          (description, unit of measure) is deliberately NOT included yet; it would be a
--          nested object inside each array element and is a separate step.
-- Warning: this script DROPS inspection_card_dv and recreates it. If the CREATE fails,
--          the step 2 view is gone; run 05_inspection_card_dv_with_unit.sql to bring it back.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS inspection_card_dv;

CREATE JSON RELATIONAL DUALITY VIEW inspection_card_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id,
    'card_status': card_status,
    'disposition': disposition,
    'opened_by': opened_by,
    'opened_at': opened_at,
    'closed_by': closed_by,
    'closed_at': closed_at,
    'unit': (
        SELECT JSON_DUALITY_OBJECT(
            'unit_id': unit_id,
            'unit_serial': unit_serial,
            'work_order_id': work_order_id
        )
        FROM production_unit
        WHERE production_unit.unit_id = inspection_card.unit_id
    ),
    'measurements': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'measurement_result_id': measurement_result_id,
                'measurement_definition_id': measurement_definition_id,
                'result_status': result_status,
                'measured_value': measured_value,
                'recorded_by': recorded_by,
                'recorded_at': recorded_at
            )
        )
        FROM measurement_result
        WHERE measurement_result.card_id = inspection_card.card_id
    )
)
FROM inspection_card;

SELECT TABLE_NAME, JSON_COLUMN_NAME, ROOT_TABLE_NAME,
       ALLOW_INSERT, ALLOW_UPDATE, ALLOW_DELETE, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection'
ORDER BY TABLE_NAME;
-- Expected: inspection_card_dv, data, inspection_card, 0, 0, 0, 1, valid
