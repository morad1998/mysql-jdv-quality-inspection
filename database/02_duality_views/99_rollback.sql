-- =====================================================================
-- D2 rollback: removes the D2 views only. Run as quality_app. Tables are not touched.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS inspection_card_dv;
