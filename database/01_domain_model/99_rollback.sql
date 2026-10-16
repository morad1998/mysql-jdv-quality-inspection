-- =====================================================================
-- D1 rollback: removes the D1 triggers and tables from quality_inspection only.
-- Run as quality_app. Destroys all D1 data. Reverse dependency order.
-- Does NOT touch jdv_spike.
-- =====================================================================
USE quality_inspection;

DROP TRIGGER IF EXISTS trg_audit_event_bd;
DROP TRIGGER IF EXISTS trg_audit_event_bu;
DROP TRIGGER IF EXISTS trg_inspection_card_bu;
DROP TRIGGER IF EXISTS trg_inspection_card_ai;
DROP TRIGGER IF EXISTS trg_inspection_card_bi;

DROP TABLE IF EXISTS audit_event;
DROP TABLE IF EXISTS attachment_metadata;
DROP TABLE IF EXISTS quality_finding;
DROP TABLE IF EXISTS checklist_result;
DROP TABLE IF EXISTS measurement_result;
DROP TABLE IF EXISTS inspection_card;
DROP TABLE IF EXISTS checklist_definition;
DROP TABLE IF EXISTS measurement_definition;
DROP TABLE IF EXISTS inspection_section;
DROP TABLE IF EXISTS production_unit;
DROP TABLE IF EXISTS work_order;
DROP TABLE IF EXISTS app_user;
