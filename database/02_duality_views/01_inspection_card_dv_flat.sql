-- =====================================================================
-- D2 / Step 1: first Duality View, read-only, flat (no nested objects yet)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Basis  : D1.9 process in the Progress Tracker: read-only view first, require
--          STATUS valid, compare the JSON with relational queries, then add one
--          nested collection at a time.
-- Tests  : blocker B-008 - does MySQL accept a Duality View over inspection_card,
--          which has the virtual generated column open_unit_key? open_unit_key is
--          deliberately NOT exposed in the document.
-- Notes  : No WITH clause, so the view is read-only (as customer_orders_dv was in Day 0).
--          Re-runnable: it drops and recreates only this view. Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS inspection_card_dv;

CREATE JSON RELATIONAL DUALITY VIEW inspection_card_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id,
    'unit_id': unit_id,
    'card_status': card_status,
    'disposition': disposition,
    'opened_by': opened_by,
    'opened_at': opened_at,
    'closed_by': closed_by,
    'closed_at': closed_at
)
FROM inspection_card;

SELECT TABLE_NAME, JSON_COLUMN_NAME, ROOT_TABLE_NAME,
       ALLOW_INSERT, ALLOW_UPDATE, ALLOW_DELETE, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection'
ORDER BY TABLE_NAME;
-- Expected: inspection_card_dv, data, inspection_card, 0, 0, 0, 1, valid
