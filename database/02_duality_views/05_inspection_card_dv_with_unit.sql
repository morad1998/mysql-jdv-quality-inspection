-- =====================================================================
-- D2 / Step 2: add the production unit as a nested object (still read-only)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Basis  : D1.9 plan: one nested part at a time, then compare the JSON with the tables.
-- Pattern: the nested single-object subquery is the same pattern that worked for
--          order_dv in Day 0 (a scalar subquery returning JSON_DUALITY_OBJECT).
--          Here there is no WITH clause, so the view stays read-only.
-- Change : unit_id moves from the root of the document into the nested "unit" object,
--          as the foreign-key column did in the Day 0 order_dv view. Whether a view
--          also allows unit_id at the root next to the nested object is untested and
--          not needed.
-- Warning: this script DROPS inspection_card_dv and recreates it. If the CREATE fails,
--          the step 1 view is gone; run 01_inspection_card_dv_flat.sql to bring it back.
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
    )
)
FROM inspection_card;

SELECT TABLE_NAME, JSON_COLUMN_NAME, ROOT_TABLE_NAME,
       ALLOW_INSERT, ALLOW_UPDATE, ALLOW_DELETE, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection'
ORDER BY TABLE_NAME;
-- Expected: inspection_card_dv, data, inspection_card, 0, 0, 0, 1, valid
