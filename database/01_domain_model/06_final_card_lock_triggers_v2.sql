-- =====================================================================
-- D2 / Step 7c fix: the child lock triggers must ignore updates that change nothing
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : root (see D-013), triggers are created with DEFINER = quality_app
-- Why    : The first version (05_final_card_lock_triggers.sql) fired on EVERY update of a result row and then
--          looked at the parent card's CURRENT status. A document write through inspection_card_edit_dv
--          updates the root first and then the child rows of the arrays it contains, including rows whose
--          values did not change. After the root had become CLOSED, those unchanged child rows hit the lock,
--          so closing a card through the edit view was refused (error 50021), and a real change to a
--          checklist answer was reported as 50021 (measurement lock) instead of 50022 (checklist lock).
-- Fix    : a child row is locked only when an UPDATE actually changes a column. The root lock trigger
--          (trg_inspection_card_bu_lock) already worked this way and is not modified.
-- Replaces: trg_measurement_result_bu_lock and trg_checklist_result_bu_lock from file 05.
-- Undo   : 98_rollback_final_card_lock.sql drops all three lock triggers.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP TRIGGER IF EXISTS trg_measurement_result_bu_lock;
DROP TRIGGER IF EXISTS trg_checklist_result_bu_lock;

DELIMITER $$

CREATE DEFINER=`quality_app`@`%` TRIGGER trg_measurement_result_bu_lock
BEFORE UPDATE ON measurement_result
FOR EACH ROW
BEGIN
    IF NOT (    NEW.card_id                   <=> OLD.card_id
            AND NEW.measurement_definition_id <=> OLD.measurement_definition_id
            AND NEW.result_status             <=> OLD.result_status
            AND NEW.measured_value            <=> OLD.measured_value
            AND NEW.recorded_by               <=> OLD.recorded_by
            AND NEW.recorded_at               <=> OLD.recorded_at)
       AND (SELECT card_status FROM inspection_card WHERE card_id = OLD.card_id) IN ('CLOSED','REJECTED') THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50021,
                MESSAGE_TEXT = 'Measurement results of a closed or rejected card cannot be changed';
    END IF;
END$$

CREATE DEFINER=`quality_app`@`%` TRIGGER trg_checklist_result_bu_lock
BEFORE UPDATE ON checklist_result
FOR EACH ROW
BEGIN
    IF NOT (    NEW.card_id                 <=> OLD.card_id
            AND NEW.checklist_definition_id <=> OLD.checklist_definition_id
            AND NEW.answer_code             <=> OLD.answer_code
            AND NEW.answered_by             <=> OLD.answered_by
            AND NEW.answered_at             <=> OLD.answered_at)
       AND (SELECT card_status FROM inspection_card WHERE card_id = OLD.card_id) IN ('CLOSED','REJECTED') THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50022,
                MESSAGE_TEXT = 'Checklist results of a closed or rejected card cannot be changed';
    END IF;
END$$

DELIMITER ;

SELECT TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_ORDER, DEFINER
FROM INFORMATION_SCHEMA.TRIGGERS
WHERE TRIGGER_SCHEMA = 'quality_inspection'
ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION, ACTION_ORDER;
-- Expected: the same 8 triggers as after file 05.
