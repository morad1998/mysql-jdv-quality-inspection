-- =====================================================================
-- D1 / Step 12E-2: positive tests and expected-failure tests
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app, AFTER 03_seed.sql, with the mysql client option --force
--          (so the script continues after each expected failure).
-- Basis  : D1 Design Pack v2 (Q3, Q5, Q6, Q7, Q8, Q9, N2)
-- Rule   : every expected failure is followed by a check that the data is unchanged.
-- Expected: exactly 8 ERROR lines (T02 1062, T03 50001, T04 50002, T06 50003,
--           T09 3819, T11 1452, T13 50010, T14 50011).
-- Re-run : this script changes data. To repeat it, reset first:
--          99_rollback.sql, 01_schema.sql, 02_rules_triggers.sql (root), 03_seed.sql.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

-- T01 ---------------------------------------------------------------------
SELECT 'T01 open card 1 for unit 1 -> EXPECT success; 2 PENDING measurements, 3 PENDING checklist items (N2)' AS test_step;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (1, 1, 1);
SELECT (SELECT COUNT(*) FROM measurement_result WHERE card_id = 1 AND result_status = 'PENDING') AS pending_measurements,
       (SELECT COUNT(*) FROM checklist_result   WHERE card_id = 1 AND answer_code   = 'PENDING') AS pending_checklist;

-- T02 ---------------------------------------------------------------------
SELECT 'T02 second active card for unit 1 -> EXPECT ERROR 1062 duplicate on uq_card_one_active_per_unit (Q3)' AS test_step;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (2, 1, 2);
SELECT COUNT(*) AS cards_for_unit_1_expect_1 FROM inspection_card WHERE unit_id = 1;

-- T03 ---------------------------------------------------------------------
SELECT 'T03 new card not starting OPEN -> EXPECT ERROR 50001' AS test_step;
INSERT INTO inspection_card (card_id, unit_id, card_status, opened_by) VALUES (3, 2, 'IN_PROGRESS', 1);
SELECT COUNT(*) AS cards_for_unit_2_expect_0 FROM inspection_card WHERE unit_id = 2;

-- T04 ---------------------------------------------------------------------
SELECT 'T04 close card 1 with unanswered checklist -> EXPECT ERROR 50002 (Q8)' AS test_step;
UPDATE inspection_card
   SET card_status = 'CLOSED', disposition = 'PASS', closed_by = 3, closed_at = UTC_TIMESTAMP()
 WHERE card_id = 1;
SELECT card_id, card_status, disposition FROM inspection_card WHERE card_id = 1;   -- expect OPEN, NULL

-- T05 ---------------------------------------------------------------------
SELECT 'T05 record results and answer all checklist items on card 1 -> EXPECT success' AS test_step;
UPDATE measurement_result
   SET result_status = 'RECORDED', measured_value = 1000.250, recorded_by = 1, recorded_at = UTC_TIMESTAMP()
 WHERE card_id = 1 AND measurement_definition_id = 1;
UPDATE measurement_result
   SET result_status = 'NOT_APPLICABLE', recorded_by = 1, recorded_at = UTC_TIMESTAMP()
 WHERE card_id = 1 AND measurement_definition_id = 2;
UPDATE checklist_result
   SET answer_code = 'YES', answered_by = 1, answered_at = UTC_TIMESTAMP()
 WHERE card_id = 1;
SELECT result_status, COUNT(*) AS n FROM measurement_result WHERE card_id = 1 GROUP BY result_status;  -- expect NOT_APPLICABLE 1, RECORDED 1
SELECT answer_code,   COUNT(*) AS n FROM checklist_result   WHERE card_id = 1 GROUP BY answer_code;    -- expect YES 3

-- T06 ---------------------------------------------------------------------
SELECT 'T06 raise a CRITICAL finding, then close card 1 -> EXPECT ERROR 50003 (Q8)' AS test_step;
INSERT INTO quality_finding (finding_id, card_id, severity, description, raised_by)
VALUES (1, 1, 'CRITICAL', 'Demo critical finding for test', 1);
UPDATE inspection_card
   SET card_status = 'CLOSED', disposition = 'PASS', closed_by = 3, closed_at = UTC_TIMESTAMP()
 WHERE card_id = 1;
SELECT card_id, card_status, disposition FROM inspection_card WHERE card_id = 1;   -- expect OPEN, NULL

-- T07 ---------------------------------------------------------------------
SELECT 'T07 resolve the finding, then close card 1 -> EXPECT success; open_unit_key becomes NULL' AS test_step;
UPDATE quality_finding SET finding_status = 'RESOLVED', resolved_at = UTC_TIMESTAMP() WHERE finding_id = 1;
UPDATE inspection_card
   SET card_status = 'CLOSED', disposition = 'PASS', closed_by = 3, closed_at = UTC_TIMESTAMP()
 WHERE card_id = 1;
SELECT card_id, card_status, disposition, open_unit_key FROM inspection_card WHERE card_id = 1;   -- expect CLOSED, PASS, NULL

-- T08 ---------------------------------------------------------------------
SELECT 'T08 retest: open card 2 on unit 1 -> EXPECT success because card 1 is closed (Q3, Q5)' AS test_step;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (2, 1, 2);
SELECT card_id, card_status, open_unit_key FROM inspection_card WHERE unit_id = 1 ORDER BY card_id;   -- expect card 1 CLOSED/NULL, card 2 OPEN/1
SELECT (SELECT COUNT(*) FROM measurement_result WHERE card_id = 2 AND result_status = 'PENDING') AS pending_measurements,
       (SELECT COUNT(*) FROM checklist_result   WHERE card_id = 2 AND answer_code   = 'PENDING') AS pending_checklist;   -- expect 2, 3

-- T09 ---------------------------------------------------------------------
SELECT 'T09 set a disposition on an OPEN card -> EXPECT ERROR 3819 (check chk_card_disposition_final)' AS test_step;
UPDATE inspection_card SET disposition = 'PASS' WHERE card_id = 2;
SELECT card_id, card_status, disposition FROM inspection_card WHERE card_id = 2;   -- expect OPEN, NULL

-- T10 ---------------------------------------------------------------------
SELECT 'T10 move card 2 to REJECTED with disposition REJECT -> EXPECT success (REJECTED is final; Q8 rules apply only to CLOSED)' AS test_step;
UPDATE inspection_card
   SET card_status = 'REJECTED', disposition = 'REJECT', closed_by = 3, closed_at = UTC_TIMESTAMP()
 WHERE card_id = 2;
SELECT card_id, card_status, disposition, open_unit_key FROM inspection_card WHERE card_id = 2;   -- expect REJECTED, REJECT, NULL

-- T11 ---------------------------------------------------------------------
SELECT 'T11 attachment on card 2 pointing at a finding of card 1 -> EXPECT ERROR 1452 (composite foreign key)' AS test_step;
INSERT INTO attachment_metadata (attachment_id, card_id, finding_id, file_name, mime_type, size_bytes, storage_key, uploaded_by)
VALUES (1, 2, 1, 'photo1.jpg', 'image/jpeg', 1024, 'demo/card_2/photo1.jpg', 1);
SELECT COUNT(*) AS attachments_expect_0 FROM attachment_metadata;
SELECT 'T11b valid attachments (card 1 with its own finding; card 1 without a finding) -> EXPECT success' AS test_step;
INSERT INTO attachment_metadata (attachment_id, card_id, finding_id, file_name, mime_type, size_bytes, storage_key, uploaded_by) VALUES
    (1, 1, 1,    'photo1.jpg', 'image/jpeg', 1024, 'demo/card_1/photo1.jpg', 1),
    (2, 1, NULL, 'photo2.jpg', 'image/jpeg', 2048, 'demo/card_1/photo2.jpg', 1);
SELECT COUNT(*) AS attachments_expect_2 FROM attachment_metadata;

-- T12 ---------------------------------------------------------------------
SELECT 'T12 append an audit event -> EXPECT success (Q9)' AS test_step;
INSERT INTO audit_event (actor_id, event_type, target_type, target_id, details)
VALUES (1, 'CARD_OPENED', 'inspection_card', 1, JSON_OBJECT('note', 'demo event'));
SELECT audit_event_id, actor_id, event_type, target_type, target_id FROM audit_event;   -- expect 1 row

-- T13 ---------------------------------------------------------------------
SELECT 'T13 update the audit event -> EXPECT ERROR 50010 (append-only)' AS test_step;
UPDATE audit_event SET event_type = 'TAMPERED' WHERE audit_event_id = 1;
SELECT event_type FROM audit_event WHERE audit_event_id = 1;   -- expect CARD_OPENED

-- T14 ---------------------------------------------------------------------
SELECT 'T14 delete the audit event -> EXPECT ERROR 50011 (append-only)' AS test_step;
DELETE FROM audit_event WHERE audit_event_id = 1;
SELECT COUNT(*) AS audit_events_expect_1 FROM audit_event;

-- Summary -----------------------------------------------------------------
SELECT 'SUMMARY final state' AS test_step;
SELECT card_id, unit_id, card_status, disposition FROM inspection_card ORDER BY card_id;   -- expect 1 CLOSED PASS; 2 REJECTED REJECT
SELECT 'inspection_card' AS table_name, COUNT(*) AS row_count FROM inspection_card
UNION ALL SELECT 'measurement_result', COUNT(*) FROM measurement_result
UNION ALL SELECT 'checklist_result',   COUNT(*) FROM checklist_result
UNION ALL SELECT 'quality_finding',    COUNT(*) FROM quality_finding
UNION ALL SELECT 'attachment_metadata',COUNT(*) FROM attachment_metadata
UNION ALL SELECT 'audit_event',        COUNT(*) FROM audit_event;
-- Expected: 2, 4, 6, 1, 2, 1.
