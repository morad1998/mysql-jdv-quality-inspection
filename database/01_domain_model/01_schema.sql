-- =====================================================================
-- D1 / Step 12A: relational schema for the manufacturing quality-inspection demo
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app (application account)
-- Basis  : D1 Design Pack v2 (decisions Q1-Q9, N1-N7 accepted)
-- Notes  : - All status/severity/role values are DEMO vocabulary, not a company standard.
--          - No DROP statements here. To undo, run 99_rollback.sql.
--          - Plain ASCII only (safe for Windows PowerShell piping).
--          - Timestamps are UTC.
-- =====================================================================
USE quality_inspection;

-- 1. app_user (N1: demo roles) -----------------------------------------
CREATE TABLE app_user (
    user_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username     VARCHAR(50)  NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    role_code    VARCHAR(20)  NOT NULL,
    is_active    TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_app_user_username (username),
    CONSTRAINT chk_app_user_role   CHECK (role_code IN ('INSPECTOR','SUPERVISOR')),
    CONSTRAINT chk_app_user_active CHECK (is_active IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Demo actors and roles (demo vocabulary)';

-- 2. work_order (Q1: manually seeded) ----------------------------------
CREATE TABLE work_order (
    work_order_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    work_order_number VARCHAR(30)  NOT NULL,
    product_model     VARCHAR(60)  NOT NULL,
    planned_quantity  INT UNSIGNED NOT NULL,
    created_at        DATETIME     NOT NULL DEFAULT (UTC_TIMESTAMP()),
    PRIMARY KEY (work_order_id),
    UNIQUE KEY uq_work_order_number (work_order_number),
    CONSTRAINT chk_work_order_qty CHECK (planned_quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Manufacturing demand and context; seeded manually in the demo';

-- 3. production_unit (Q2: surrogate id + unique serial) ----------------
CREATE TABLE production_unit (
    unit_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    work_order_id INT UNSIGNED NOT NULL,
    unit_serial   VARCHAR(40)  NOT NULL,
    created_at    DATETIME     NOT NULL DEFAULT (UTC_TIMESTAMP()),
    PRIMARY KEY (unit_id),
    UNIQUE KEY uq_production_unit_serial (unit_serial),
    KEY ix_production_unit_wo (work_order_id),
    CONSTRAINT fk_production_unit_work_order
        FOREIGN KEY (work_order_id) REFERENCES work_order (work_order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Physical item being inspected';

-- 4. inspection_section (reference data; not versioned - Q4 limitation) -
CREATE TABLE inspection_section (
    section_id   INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    section_code VARCHAR(20)       NOT NULL,
    section_name VARCHAR(100)      NOT NULL,
    sort_order   SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (section_id),
    UNIQUE KEY uq_inspection_section_code (section_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Reusable section definition; definitions are not versioned (Q4 limitation)';

-- 5. measurement_definition ---------------------------------------------
CREATE TABLE measurement_definition (
    measurement_definition_id INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    section_id                INT UNSIGNED  NOT NULL,
    checkpoint_code           VARCHAR(30)   NOT NULL,
    description               VARCHAR(200)  NOT NULL,
    unit_of_measure           VARCHAR(20)   NOT NULL,
    min_value                 DECIMAL(10,3) NULL,
    max_value                 DECIMAL(10,3) NULL,
    PRIMARY KEY (measurement_definition_id),
    UNIQUE KEY uq_measurement_def_code (section_id, checkpoint_code),
    CONSTRAINT fk_measurement_def_section
        FOREIGN KEY (section_id) REFERENCES inspection_section (section_id),
    CONSTRAINT chk_measurement_def_range
        CHECK (min_value IS NULL OR max_value IS NULL OR min_value <= max_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Expected measured checkpoint (demo tolerance values)';

-- 6. checklist_definition ------------------------------------------------
CREATE TABLE checklist_definition (
    checklist_definition_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    section_id              INT UNSIGNED NOT NULL,
    checkpoint_code         VARCHAR(30)  NOT NULL,
    description             VARCHAR(200) NOT NULL,
    PRIMARY KEY (checklist_definition_id),
    UNIQUE KEY uq_checklist_def_code (section_id, checkpoint_code),
    CONSTRAINT fk_checklist_def_section
        FOREIGN KEY (section_id) REFERENCES inspection_section (section_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Expected yes/no/not-applicable checkpoint';

-- 7. inspection_card (Q3, Q5, Q6) ---------------------------------------
-- open_unit_key is a VIRTUAL generated column. It holds unit_id while the card is
-- OPEN or IN_PROGRESS and NULL otherwise. A UNIQUE index on it allows at most one
-- active card per unit, because MySQL allows many NULLs in a UNIQUE index (Q3).
CREATE TABLE inspection_card (
    card_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    unit_id       INT UNSIGNED NOT NULL,
    card_status   VARCHAR(20)  NOT NULL DEFAULT 'OPEN',
    disposition   VARCHAR(10)  NULL,
    opened_by     INT UNSIGNED NOT NULL,
    opened_at     DATETIME     NOT NULL DEFAULT (UTC_TIMESTAMP()),
    closed_by     INT UNSIGNED NULL,
    closed_at     DATETIME     NULL,
    open_unit_key INT UNSIGNED GENERATED ALWAYS AS
        (CASE WHEN card_status IN ('OPEN','IN_PROGRESS') THEN unit_id ELSE NULL END) VIRTUAL,
    PRIMARY KEY (card_id),
    UNIQUE KEY uq_card_one_active_per_unit (open_unit_key),
    KEY ix_card_unit (unit_id),
    KEY ix_card_status (card_status),
    CONSTRAINT fk_card_unit      FOREIGN KEY (unit_id)   REFERENCES production_unit (unit_id),
    CONSTRAINT fk_card_opened_by FOREIGN KEY (opened_by) REFERENCES app_user (user_id),
    CONSTRAINT fk_card_closed_by FOREIGN KEY (closed_by) REFERENCES app_user (user_id),
    CONSTRAINT chk_card_status CHECK (card_status IN ('OPEN','IN_PROGRESS','CLOSED','REJECTED')),
    CONSTRAINT chk_card_disposition_value CHECK (disposition IS NULL OR disposition IN ('PASS','REJECT')),
    -- Disposition exists only on a final card; a CLOSED card must have one (Q6).
    CONSTRAINT chk_card_disposition_final CHECK (
        (disposition IS NULL OR card_status IN ('CLOSED','REJECTED'))
        AND (card_status <> 'CLOSED' OR disposition IS NOT NULL)),
    -- Close fields are set exactly when the card is final.
    CONSTRAINT chk_card_close_fields CHECK (
        (card_status IN ('OPEN','IN_PROGRESS') AND closed_at IS NULL AND closed_by IS NULL)
        OR (card_status IN ('CLOSED','REJECTED') AND closed_at IS NOT NULL AND closed_by IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Inspection instance and lifecycle; a retest is a new card (Q5)';

-- 8. measurement_result (Q5, N2) -----------------------------------------
CREATE TABLE measurement_result (
    measurement_result_id     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    card_id                   INT UNSIGNED  NOT NULL,
    measurement_definition_id INT UNSIGNED  NOT NULL,
    result_status             VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    measured_value            DECIMAL(10,3) NULL,
    recorded_by               INT UNSIGNED  NULL,
    recorded_at               DATETIME      NULL,
    PRIMARY KEY (measurement_result_id),
    UNIQUE KEY uq_measurement_result (card_id, measurement_definition_id),
    KEY ix_measurement_result_def (measurement_definition_id),
    CONSTRAINT fk_measurement_result_card FOREIGN KEY (card_id) REFERENCES inspection_card (card_id),
    CONSTRAINT fk_measurement_result_def  FOREIGN KEY (measurement_definition_id)
        REFERENCES measurement_definition (measurement_definition_id),
    CONSTRAINT fk_measurement_result_user FOREIGN KEY (recorded_by) REFERENCES app_user (user_id),
    CONSTRAINT chk_measurement_result_status CHECK (result_status IN ('PENDING','RECORDED','NOT_APPLICABLE')),
    CONSTRAINT chk_measurement_result_value CHECK (
        (result_status = 'RECORDED' AND measured_value IS NOT NULL)
        OR (result_status IN ('PENDING','NOT_APPLICABLE') AND measured_value IS NULL)),
    CONSTRAINT chk_measurement_result_who CHECK (
        (result_status = 'PENDING' AND recorded_by IS NULL AND recorded_at IS NULL)
        OR (result_status <> 'PENDING' AND recorded_by IS NOT NULL AND recorded_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Captured numeric result; PENDING rows are created when a card opens (N2)';

-- 9. checklist_result (Q5, Q8, N2) ---------------------------------------
CREATE TABLE checklist_result (
    checklist_result_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    card_id                 INT UNSIGNED NOT NULL,
    checklist_definition_id INT UNSIGNED NOT NULL,
    answer_code             VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    answered_by             INT UNSIGNED NULL,
    answered_at             DATETIME     NULL,
    PRIMARY KEY (checklist_result_id),
    UNIQUE KEY uq_checklist_result (card_id, checklist_definition_id),
    KEY ix_checklist_result_def (checklist_definition_id),
    KEY ix_checklist_result_card_answer (card_id, answer_code),
    CONSTRAINT fk_checklist_result_card FOREIGN KEY (card_id) REFERENCES inspection_card (card_id),
    CONSTRAINT fk_checklist_result_def  FOREIGN KEY (checklist_definition_id)
        REFERENCES checklist_definition (checklist_definition_id),
    CONSTRAINT fk_checklist_result_user FOREIGN KEY (answered_by) REFERENCES app_user (user_id),
    CONSTRAINT chk_checklist_result_answer CHECK (answer_code IN ('PENDING','YES','NO','NOT_APPLICABLE')),
    CONSTRAINT chk_checklist_result_who CHECK (
        (answer_code = 'PENDING' AND answered_by IS NULL AND answered_at IS NULL)
        OR (answer_code <> 'PENDING' AND answered_by IS NOT NULL AND answered_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Captured checklist outcome; PENDING means unanswered (Q8, N2)';

-- 10. quality_finding (Q6, Q8) -------------------------------------------
-- UNIQUE (finding_id, card_id) lets attachment_metadata prove that a finding
-- belongs to the same card as the attachment.
CREATE TABLE quality_finding (
    finding_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    card_id        INT UNSIGNED NOT NULL,
    severity       VARCHAR(10)  NOT NULL,
    finding_status VARCHAR(10)  NOT NULL DEFAULT 'OPEN',
    description    VARCHAR(500) NOT NULL,
    raised_by      INT UNSIGNED NOT NULL,
    raised_at      DATETIME     NOT NULL DEFAULT (UTC_TIMESTAMP()),
    resolved_at    DATETIME     NULL,
    PRIMARY KEY (finding_id),
    UNIQUE KEY uq_finding_card (finding_id, card_id),
    KEY ix_finding_card_rule (card_id, severity, finding_status),
    CONSTRAINT fk_finding_card FOREIGN KEY (card_id)   REFERENCES inspection_card (card_id),
    CONSTRAINT fk_finding_user FOREIGN KEY (raised_by) REFERENCES app_user (user_id),
    CONSTRAINT chk_finding_severity CHECK (severity IN ('MINOR','MAJOR','CRITICAL')),
    CONSTRAINT chk_finding_status   CHECK (finding_status IN ('OPEN','RESOLVED')),
    CONSTRAINT chk_finding_resolved CHECK (
        (finding_status = 'OPEN' AND resolved_at IS NULL)
        OR (finding_status = 'RESOLVED' AND resolved_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Observed nonconformance';

-- 11. attachment_metadata (Q7: bytes stay outside MySQL) ------------------
-- When finding_id is NULL the composite foreign key is not checked (MATCH SIMPLE).
CREATE TABLE attachment_metadata (
    attachment_id INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    card_id       INT UNSIGNED    NOT NULL,
    finding_id    INT UNSIGNED    NULL,
    file_name     VARCHAR(255)    NOT NULL,
    mime_type     VARCHAR(100)    NOT NULL,
    size_bytes    BIGINT UNSIGNED NOT NULL,
    storage_key   VARCHAR(500)    NOT NULL,
    uploaded_by   INT UNSIGNED    NOT NULL,
    uploaded_at   DATETIME        NOT NULL DEFAULT (UTC_TIMESTAMP()),
    PRIMARY KEY (attachment_id),
    UNIQUE KEY uq_attachment_storage_key (storage_key),
    KEY ix_attachment_card (card_id),
    KEY ix_attachment_finding (finding_id, card_id),
    CONSTRAINT fk_attachment_card    FOREIGN KEY (card_id) REFERENCES inspection_card (card_id),
    CONSTRAINT fk_attachment_finding FOREIGN KEY (finding_id, card_id)
        REFERENCES quality_finding (finding_id, card_id),
    CONSTRAINT fk_attachment_user    FOREIGN KEY (uploaded_by) REFERENCES app_user (user_id),
    CONSTRAINT chk_attachment_size CHECK (size_bytes > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='External object reference and metadata only; file bytes are not stored here';

-- 12. audit_event (Q9, N7) -----------------------------------------------
-- target_id has no foreign key because it points at different tables by target_type.
CREATE TABLE audit_event (
    audit_event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    actor_id       INT UNSIGNED    NOT NULL,
    event_type     VARCHAR(40)     NOT NULL,
    event_time     DATETIME(3)     NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
    target_type    VARCHAR(40)     NOT NULL,
    target_id      BIGINT UNSIGNED NOT NULL,
    details        JSON            NULL,
    PRIMARY KEY (audit_event_id),
    KEY ix_audit_target (target_type, target_id),
    KEY ix_audit_time (event_time),
    CONSTRAINT fk_audit_actor FOREIGN KEY (actor_id) REFERENCES app_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Append-only activity record (enforced by triggers in 02_rules_triggers.sql)';
