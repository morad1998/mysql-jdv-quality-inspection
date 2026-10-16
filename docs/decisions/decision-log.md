# Project Decision Log

## D-001 - Greenfield implementation

- Status: Approved
- Date: 2026-10-02
- Decision: Build the bounty application completely from scratch in a dedicated repository.
- Reason: Keep the public bounty implementation reproducible and separate from the existing QMS Performance Card application.
- Constraint: QMS documents may be consulted only for general architectural, testing, documentation, and manufacturing-domain lessons.
- Constraint: Do not copy proprietary data, credentials, infrastructure details, Oracle-specific SQL, or internal source code.

## D-002 - Primary application scenario

- Status: Approved
- Date: 2026-10-02
- Decision: Use a manufacturing quality-inspection application as the bounty scenario.
- Scope: Work orders, production units, inspection cards, sections, measurements, checklist results, findings, attachment metadata, and audit events.

## D-003 - Database runtime

- Status: Approved
- Date: 2026-10-02
- Decision: Use MySQL Community Server 9.7.2 in Docker.
- Image: mysql:9.7.2
- Reason: Pinning the exact patch version improves reproducibility.
- Verification: The image and included MySQL client were successfully inspected and executed.

## D-004 - Database connectivity

- Status: Approved
- Date: 2026-10-02
- Decision: Use host port 3307 for the local MySQL container.
- Reason: Avoid conflict with the conventional MySQL port 3306.

## D-005 - Development stack

- Status: Approved
- Date: 2026-10-02
- Decision: Use Node.js, TypeScript, React, and a server-side API boundary.
- Security rule: Database credentials and optional AI-provider credentials must not be exposed to the browser.

## D-006 - Evidence standard

- Status: Approved
- Date: 2026-10-02
- Decision: No capability is complete until demonstrated through executed commands and actual output.
- Required proof: JSON verification, relational verification, tested-version evidence, and recorded failures or limitations.

## D-007 - JSON Duality View validation

- Status: Approved
- Date: 2026-10-02
- Decision: Run a minimum official customer-and-order capability spike before designing the full manufacturing schema.
- Required proof: View creation, document read, controlled DML, base-table persistence, invalid-document rejection, and rollback behavior.

## D-008 - AI integration

- Status: Approved
- Date: 2026-10-02
- Decision: Keep AI integration disabled during the initial database and application build.
- Future rule: Any AI assistant must use a restricted, read-only context and must not receive unrestricted database access.

## D-009 - D1 domain vocabulary and lifecycle rules

- Status: Approved
- Date: 2026-10-16
- Decision: Adopt the D1 demo vocabulary. Card status: OPEN, IN_PROGRESS, CLOSED, REJECTED. Disposition: PASS or REJECT, set only on a final card. Finding severity: MINOR, MAJOR, CRITICAL. Finding status: OPEN, RESOLVED. Measurement result: PENDING, RECORDED, NOT_APPLICABLE. Checklist answer: PENDING, YES, NO, NOT_APPLICABLE.
- Scope: Work orders are seeded manually with deterministic scripts. Units are identified by a surrogate unit_id plus a unique unit_serial. A unit may have several cards over time; a retest is a new card and never an overwrite. Attachment bytes stay outside MySQL (metadata only). audit_event requires actor_id, event_type, event_time, target_type and target_id and is append-only.
- Constraint: Every value is a demo vocabulary for a public example. None is claimed to be an organizational or production standard.
- Constraint: Checkpoint definitions are not versioned in the schema. This is a stated limitation of the example.
- Verification: Tests T01 to T14 in database/01_domain_model/04_tests.sql; output in docs/evidence/day-1/04-tests-output.txt.

## D-010 - Demo roles and pre-created pending rows

- Status: Approved
- Date: 2026-10-16
- Decision: Two demo roles are stored in app_user.role_code: INSPECTOR and SUPERVISOR. When a card opens, trigger trg_inspection_card_ai creates one PENDING measurement_result row per measurement_definition and one PENDING checklist_result row per checklist_definition.
- Reason: "Unanswered checklist item" becomes a queryable state instead of a missing row.
- Constraint: Role permissions are not enforced by the database in D1. Enforcement belongs to the API layer in a later phase.
- Verification: T01 and T08 show 2 pending measurements and 3 pending checklist items on each newly opened card.

## D-011 - REJECTED is a final status

- Status: Approved
- Date: 2026-10-16
- Decision: REJECTED is a final status alongside CLOSED. Both require closed_by and closed_at. A disposition is allowed only on a final card and is mandatory for CLOSED. The close checks (unanswered checklist item, open CRITICAL finding) apply only when a card moves to CLOSED.
- Reason: The original decisions did not define REJECTED. This reading was proposed on 2026-10-16 and no objection was raised after test T10 showed the behavior.
- Constraint: A REJECTED card may still have pending checklist items. Revisit if rejection should require the same checks.
- Verification: T09 (disposition on an OPEN card rejected with error 3819) and T10 (card moved to REJECTED).

## D-012 - One active card per unit

- Status: Approved
- Date: 2026-10-16
- Decision: Enforce at most one OPEN or IN_PROGRESS card per unit with a virtual generated column open_unit_key (the unit_id while the card is active, NULL otherwise) and a UNIQUE index uq_card_one_active_per_unit.
- Reason: MySQL allows many NULL values in a unique index, so final cards do not block a retest.
- Constraint: Compatibility of this generated column with JSON Duality Views is not yet proven (see B-008).
- Verification: T02 (error 1062 on the unique index); T07, T08 and T10 (key becomes NULL when a card is final, and a retest card opens).

## D-013 - Business rules are enforced in the database

- Status: Approved
- Date: 2026-10-16
- Decision: Triggers enforce the close rules and the append-only audit table, using user-defined error numbers: 50001 new card must start OPEN; 50002 unanswered checklist item blocks close; 50003 open CRITICAL finding blocks close; 50010 audit_event update blocked; 50011 audit_event delete blocked. CHECK constraints enforce disposition and result rules. A composite foreign key ensures an attachment's finding belongs to the same card.
- Constraint: Triggers are created by the root account with DEFINER quality_app, because a non-root account can fail to create triggers (error 1419) when binary logging is on.
- Verification: T03, T04, T06, T09, T11, T13 and T14 each raised the expected error, and a state check after each showed the data unchanged.

## D-014 - Project documents are versioned

- Status: Approved
- Date: 2026-10-16
- Decision: Every design document carries a version in its file name and is never overwritten; a change creates the next version. Word versions are kept in the owner's cloud storage. Markdown and SQL sources are kept in this repository. Each document states the Git commit it is based on.

## D-015 - AI assistant scope (amends D-008)

- Status: Approved (design only; not implemented)
- Date: 2026-10-16
- Decision: AI stays disabled by default, but one read-only assistant is in scope. It explains an inspection card, produces a full work-order report, and answers manufacturing statistics questions that the schema can support.
- Scope: Two read-only document views (one per card, one per work order) plus fixed aggregate SQL views, because statistics are aggregates and Duality Views are not the right tool for them. A SELECT-only database account. Fixed read-only tool functions; the model never writes SQL and never writes data. Synthetic data only. Each question is logged as an audit_event with event_type AI_QUERY.
- Provider: A hosted model called with the owner's own API key through a thin adapter. AI_PROVIDER stays disabled by default. The specific provider is not yet chosen (see B-009).
- Constraint: Credentials stay server-side (D-005).
- Constraint: Before enabling, test a write request, prompt-injection text inside a finding description, and a request for data outside the views.

## D-016 - Offline scope

- Status: Approved (design only; not implemented)
- Date: 2026-10-16
- Decision: Offline support covers edits to inspection cards already downloaded to the device. Each queued edit carries the ETag of the document it was based on. If MySQL rejects the replay as stale (error 6494, proven in Day 0 and replayed on 2026-10-16), the user is shown both versions and chooses. Offline card creation and offline attachments are out of scope.
- Constraint: A retry after a lost response can look like a conflict. The app must re-read the document and compare before reporting one.

## D-017 - Backup set and restore verification standard

- Status: Approved
- Date: 2026-10-16
- Decision: A backup set consists of a Git bundle, a logical dump of quality_inspection and jdv_spike, baseline row counts, a runtime manifest and SHA256 hashes, stored outside the repository. A backup counts as valid only after a restore rehearsal in a throwaway container with random passwords, compared against the live database, with the live database left untouched.
- Reason: A backup that has never been restored is only an assumption.
- Constraint: The dump contains no users or grants. After loading it, the application account needs rights on jdv_spike, because the Duality Views there are defined by quality_app and fail with error 1356 without them (see B-013).
- Constraint: Dumps are created inside the container and copied out with docker cp, because Windows PowerShell redirection changes the encoding.
- Verification: docs/evidence/day-1/backup/ and docs/runbooks/restore-from-backup.md.

## D-018 - inspection_card_dv exposes real columns only

- Status: Approved
- Date: 2026-10-16
- Decision: The first Duality View over inspection_card, inspection_card_dv, is read-only (no WITH clause) and exposes the card columns card_id (as _id), unit_id, card_status, disposition, opened_by, opened_at, closed_by and closed_at. The generated column open_unit_key is an enforcement mechanism (D-012) and is not exposed.
- Constraint: MySQL writes DATETIME values inside a document as plain strings in the form "2026-10-16 01:13:25.000000": a space between date and time, microseconds, no T and no Z. The values are stored in UTC but the document does not say so. The API layer must label or convert them.
- Constraint: SQL NULL appears in a document as JSON null.
- Constraint: A no-change update through a read-only view (setting a field to the value it already has) is accepted silently. A real change is refused with error 6497 (Missing UPDATE tag on the column and path).
- Verification: docs/evidence/day-2/ (V1 to V5, F1 to F5) and database/02_duality_views/.
