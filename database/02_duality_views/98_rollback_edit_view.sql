-- =====================================================================
-- Rollback: removes the edit view only. Run as quality_app. Tables and the read view are not touched.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS inspection_card_edit_dv;
