-- =====================================================================
-- Rollback of D2 step 7c: removes only the three lock triggers. Run as root. Data is not touched.
-- =====================================================================
USE quality_inspection;

DROP TRIGGER IF EXISTS trg_inspection_card_bu_lock;
DROP TRIGGER IF EXISTS trg_measurement_result_bu_lock;
DROP TRIGGER IF EXISTS trg_checklist_result_bu_lock;
