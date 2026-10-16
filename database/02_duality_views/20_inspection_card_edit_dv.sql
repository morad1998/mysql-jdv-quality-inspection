-- =====================================================================
-- D2 / Step 7a: the first WRITABLE view, root object only (the B-008 test)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Design : a SEPARATE edit view. The read view inspection_card_dv is NOT touched.
--          Modification tags work per object, so the writable fields are exactly the fields
--          this object projects. Only the close path is exposed: card_status, disposition,
--          closed_by, closed_at. unit_id and opened_by are not projected, so a document
--          cannot change them.
-- Tag    : WITH (UPDATE) only. No INSERT and no DELETE, so documents cannot create or remove cards.
-- B-008  : inspection_card has the virtual generated column open_unit_key. This view does not
--          project it. Creating a WRITABLE view over this table is the open question.
-- Rule   : if the CREATE fails, send the error text; that is the B-008 finding.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS inspection_card_edit_dv;

CREATE JSON RELATIONAL DUALITY VIEW inspection_card_edit_dv AS
SELECT JSON_DUALITY_OBJECT(
    WITH (UPDATE)
    '_id': card_id,
    'card_status': card_status,
    'disposition': disposition,
    'closed_by': closed_by,
    'closed_at': closed_at
)
FROM inspection_card;

SELECT TABLE_NAME, JSON_COLUMN_NAME, ROOT_TABLE_NAME,
       ALLOW_INSERT, ALLOW_UPDATE, ALLOW_DELETE, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection'
ORDER BY TABLE_NAME;
-- Expected: inspection_card_dv (read-only, valid) and
--           inspection_card_edit_dv, data, inspection_card, 0, 1, 0, 0, valid
